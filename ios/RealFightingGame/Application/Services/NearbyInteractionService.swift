import Combine
import Foundation
import NearbyInteraction
import os.log
import simd

@MainActor
final class NearbyInteractionService: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case unsupported
        case unauthorized
        case waitingForPeer
        case running
        case suspended
        case invalidated(String)
    }

    struct Reading: Equatable {
        let distanceMeters: Double?
        let azimuthRadians: Double?
        let elevationRadians: Double?
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var reading: Reading?
    @Published private(set) var encodedDiscoveryToken: String?

    private var session: NISession?
    private var peerToken: NIDiscoveryToken?
    private var logger = Logger(subsystem: "RealFightingGame", category: "NearbyInteraction")

    func prepare() {
        guard session == nil else {
            refreshAuthorization()
            return
        }
        guard NISession.isSupported else {
            status = .unsupported
            logger.error("Nearby Interaction is not supported on this device")
            return
        }
        let session = NISession()
        session.delegate = self
        self.session = session
        refreshAuthorization()
        refreshLocalToken()
    }

    func setPeerToken(fromBase64 encoded: String) {
        guard !encoded.isEmpty else { return }
        do {
            let token = try Self.decodeDiscoveryToken(encoded)
            peerToken = token
            logger.debug("Peer discovery token received, attempting to start session")
            resumeIfPossible()
        } catch {
            logger.error("Failed to decode peer token: \(error.localizedDescription, privacy: .public)")
            status = .invalidated("相手端末の検出情報を読み取れませんでした")
        }
    }

    func invalidate() {
        guard let session else { return }
        session.invalidate()
        self.session = nil
        peerToken = nil
        reading = nil
        encodedDiscoveryToken = nil
        status = .idle
    }

    func suspend() {
        session?.pause()
        status = .suspended
    }

    func clearPeerToken() {
        peerToken = nil
        reading = nil
        status = .waitingForPeer
    }

    func resume() {
        refreshAuthorization()
        refreshLocalToken()
        resumeIfPossible()
    }

    private func refreshAuthorization() {
        if #available(iOS 15.0, *) {
            switch NISession.authorizationStatus {
            case .notDetermined:
                status = peerToken == nil ? .waitingForPeer : .idle
            case .restricted, .denied:
                status = .unauthorized
            case .authorized:
                if peerToken == nil {
                    status = .waitingForPeer
                } else {
                    status = .idle
                }
            @unknown default:
                status = .unauthorized
            }
        } else {
            if peerToken == nil {
                status = .waitingForPeer
            } else {
                status = .idle
            }
        }
    }

    private func refreshLocalToken() {
        guard let session else { return }
        guard let token = session.discoveryToken else {
            logger.fault("Discovery token unavailable from session")
            return
        }
        do {
            let encoded = try Self.encodeDiscoveryToken(token)
            if encodedDiscoveryToken != encoded {
                encodedDiscoveryToken = encoded
                logger.debug("Local discovery token encoded and ready to publish")
            }
        } catch {
            logger.error("Failed to encode discovery token: \(error.localizedDescription, privacy: .public)")
            status = .invalidated("端末の検出情報を準備できませんでした")
        }
    }

    private func resumeIfPossible() {
        guard let session, let peerToken else {
            if peerToken == nil {
                status = .waitingForPeer
            }
            return
        }
        refreshAuthorization()
        guard status != .unauthorized else { return }

        let configuration = NINearbyPeerConfiguration(peerToken: peerToken)
        session.run(configuration)
        status = .running
        logger.debug("Nearby Interaction session started or resumed")
    }

    private static func encodeDiscoveryToken(_ token: NIDiscoveryToken) throws -> String {
        let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        return data.base64EncodedString()
    }

    private static func decodeDiscoveryToken(_ encoded: String) throws -> NIDiscoveryToken {
        guard let data = Data(base64Encoded: encoded) else {
            throw NSError(domain: "NearbyInteractionService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Base64 decode failed"])
        }
        guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
            throw NSError(domain: "NearbyInteractionService", code: -11, userInfo: [NSLocalizedDescriptionKey: "Token decode failed"])
        }
        return token
    }
}

extension NearbyInteractionService: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else {
            reading = nil
            status = .waitingForPeer
            return
        }
        let azimuth = object.direction.map { atan2(Double($0.x), Double($0.z)) }
        let elevation = object.direction.map { asin(Double($0.y) / max(Double(simd_length($0)), .leastNonzeroMagnitude)) }
        reading = Reading(
            distanceMeters: object.distance,
            azimuthRadians: azimuth,
            elevationRadians: elevation
        )
        status = .running
    }

    func sessionWasSuspended(_ session: NISession) {
        logger.info("Nearby Interaction session suspended")
        status = .suspended
    }

    func sessionSuspensionEnded(_ session: NISession) {
        logger.info("Nearby Interaction session suspension ended. Resuming…")
        resumeIfPossible()
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        logger.error("Nearby Interaction session invalidated: \(error.localizedDescription, privacy: .public)")
        status = .invalidated(error.localizedDescription)
        peerToken = nil
        reading = nil
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        logger.info("Nearby Interaction objects removed with reason=\(String(describing: reason), privacy: .public)")
        switch reason {
        case .peerEnded, .peerCancelled:
            status = .waitingForPeer
        case .timeout:
            status = .suspended
        case .unknown:
            status = .invalidated("通信が不安定です")
        @unknown default:
            status = .invalidated("不明なエラーが発生しました")
        }
        reading = nil
    }
}
