import CoreLocation
import Foundation
import OSLog

protocol LocationService {
    func requestWhenInUseAuthorization() async
    func currentLocation() async throws -> CLLocationCoordinate2D
    func locationUpdates() -> AsyncStream<Result<CLLocationCoordinate2D, Error>>
    func stopLocationUpdates()
}

final class CoreLocationService: NSObject, LocationService, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var singleLocationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var streamContinuation: AsyncStream<Result<CLLocationCoordinate2D, Error>>.Continuation?
    private let logger = Logger(subsystem: "RealFightingGame", category: "LocationService")

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestWhenInUseAuthorization() async {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = manager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async throws -> CLLocationCoordinate2D {
        if let cached = manager.location, isLocationAcceptable(cached) {
            logger.debug("currentLocation immediate lat: \(cached.coordinate.latitude), lon: \(cached.coordinate.longitude), acc: \(cached.horizontalAccuracy)")
            return cached.coordinate
        } else if let cached = manager.location {
            logger.debug("currentLocation cached ignored age: \(Date().timeIntervalSince(cached.timestamp)), acc: \(cached.horizontalAccuracy)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                self.singleLocationContinuation = continuation
                self.manager.requestLocation()
            }
        }
    }

    func locationUpdates() -> AsyncStream<Result<CLLocationCoordinate2D, Error>> {
        AsyncStream { continuation in
            Task { @MainActor in
                self.streamContinuation?.finish()
                self.streamContinuation = continuation
                continuation.onTermination = { _ in
                    Task { @MainActor in
                        self.streamContinuation = nil
                        self.manager.stopUpdatingLocation()
                    }
                }
                self.manager.startUpdatingLocation()
            }
        }
    }

    func stopLocationUpdates() {
        Task { @MainActor in
            self.manager.stopUpdatingLocation()
            self.streamContinuation?.finish()
            self.streamContinuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        guard isLocationAcceptable(latest) else {
            logger.debug("locationUpdates ignored lat: \(latest.coordinate.latitude), lon: \(latest.coordinate.longitude), acc: \(latest.horizontalAccuracy)")
            return
        }
        if let continuation = singleLocationContinuation {
            singleLocationContinuation = nil
            continuation.resume(returning: latest.coordinate)
        }
        logger.debug("locationUpdates stream lat: \(latest.coordinate.latitude), lon: \(latest.coordinate.longitude), acc: \(latest.horizontalAccuracy)")
        streamContinuation?.yield(.success(latest.coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let continuation = singleLocationContinuation {
            singleLocationContinuation = nil
            continuation.resume(throwing: error)
        }
        streamContinuation?.yield(.failure(error))
    }

    private func isLocationAcceptable(_ location: CLLocation) -> Bool {
        let age = abs(location.timestamp.timeIntervalSinceNow)
        let accuracy = location.horizontalAccuracy
        return age <= 10 && accuracy >= 0 && accuracy <= 50
    }
}

struct MockLocationService: LocationService {
    let coordinate: CLLocationCoordinate2D
    let updates: [CLLocationCoordinate2D]
    let updateIntervalNanoseconds: UInt64
    private let logger = Logger(subsystem: "RealFightingGame", category: "MockLocationService")

    init(
        coordinate: CLLocationCoordinate2D = .init(latitude: 34.651562, longitude: 135.591204),
        updates: [CLLocationCoordinate2D] = [],
        updateIntervalNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.coordinate = coordinate
        self.updates = updates
        self.updateIntervalNanoseconds = updateIntervalNanoseconds
    }

    func requestWhenInUseAuthorization() async {}

    func currentLocation() async throws -> CLLocationCoordinate2D {
        logger.debug("[Mock] currentLocation lat: \(coordinate.latitude), lon: \(coordinate.longitude)")
        return coordinate
    }

    func locationUpdates() -> AsyncStream<Result<CLLocationCoordinate2D, Error>> {
        let sequence = updates.isEmpty ? [coordinate] : updates
        return AsyncStream { continuation in
            Task {
                for coord in sequence {
                    logger.debug("[Mock] locationUpdates stream lat: \(coord.latitude), lon: \(coord.longitude)")
                    continuation.yield(.success(coord))
                    if updateIntervalNanoseconds > 0 {
                        try await Task.sleep(nanoseconds: updateIntervalNanoseconds)
                    }
                }
                continuation.finish()
            }
        }
    }

    func stopLocationUpdates() {}
}
