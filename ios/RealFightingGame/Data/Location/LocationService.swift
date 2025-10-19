import CoreLocation
import Foundation

struct LocationSample {
    let coordinate: CLLocationCoordinate2D
    let altitude: CLLocationDistance?
    let horizontalAccuracy: CLLocationAccuracy
    let verticalAccuracy: CLLocationAccuracy?
    let heading: CLLocationDirection?
    let headingAccuracy: CLLocationDirection?
    let course: CLLocationDirection?
    let timestamp: Date
}

protocol LocationService {
    func requestWhenInUseAuthorization() async
    func currentLocation() async throws -> CLLocationCoordinate2D
    func locationUpdates() -> AsyncStream<Result<LocationSample, Error>>
    func stopLocationUpdates()
}

final class CoreLocationService: NSObject, LocationService, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var singleLocationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var streamContinuation: AsyncStream<Result<LocationSample, Error>>.Continuation?
    private var latestHeading: CLHeading?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.headingFilter = 1
        manager.headingOrientation = .portrait
    }

    func requestWhenInUseAuthorization() async {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = manager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        if status == .notDetermined {
            await MainActor.run {
                self.manager.requestWhenInUseAuthorization()
            }
        }
    }

    func currentLocation() async throws -> CLLocationCoordinate2D {
        if let cached = manager.location, isLocationAcceptable(cached) {
            return cached.coordinate
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                self.singleLocationContinuation = continuation
                self.manager.requestLocation()
            }
        }
    }

    func locationUpdates() -> AsyncStream<Result<LocationSample, Error>> {
        AsyncStream { continuation in
            Task { @MainActor in
                self.streamContinuation?.finish()
                self.streamContinuation = continuation
                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.streamContinuation = nil
                        self.manager.stopUpdatingLocation()
                        if CLLocationManager.headingAvailable() {
                            self.manager.stopUpdatingHeading()
                        }
                    }
                }
                self.manager.startUpdatingLocation()
                if CLLocationManager.headingAvailable() {
                    self.manager.startUpdatingHeading()
                }
            }
        }
    }

    func stopLocationUpdates() {
        Task { @MainActor in
            self.manager.stopUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                self.manager.stopUpdatingHeading()
            }
            self.streamContinuation?.finish()
            self.streamContinuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        guard isLocationAcceptable(latest) else { return }

        if let continuation = singleLocationContinuation {
            singleLocationContinuation = nil
            continuation.resume(returning: latest.coordinate)
        }

        streamContinuation?.yield(.success(makeSample(from: latest)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let continuation = singleLocationContinuation {
            singleLocationContinuation = nil
            continuation.resume(throwing: error)
        }
        streamContinuation?.yield(.failure(error))
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        latestHeading = newHeading
    }

    private func makeSample(from location: CLLocation) -> LocationSample {
        let altitude: CLLocationDistance? = location.verticalAccuracy >= 0 ? location.altitude : nil
        let verticalAccuracy: CLLocationAccuracy? = location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil
        let headingInfo = bestHeading(for: location)
        return LocationSample(
            coordinate: location.coordinate,
            altitude: altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            heading: headingInfo.value,
            headingAccuracy: headingInfo.accuracy,
            course: location.course >= 0 ? location.course : nil,
            timestamp: location.timestamp
        )
    }

    private func bestHeading(for location: CLLocation) -> (value: CLLocationDirection?, accuracy: CLLocationDirection?) {
        if let heading = latestHeading, heading.headingAccuracy >= 0 {
            let raw = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            return (normalizeHeading(raw), heading.headingAccuracy >= 0 ? heading.headingAccuracy : nil)
        }
        if location.course >= 0 {
            return (normalizeHeading(location.course), nil)
        }
        return (nil, nil)
    }

    private func normalizeHeading(_ value: CLLocationDirection) -> CLLocationDirection {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result < 0 { result += 360 }
        return result
    }

    private func isLocationAcceptable(_ location: CLLocation) -> Bool {
        let age = abs(location.timestamp.timeIntervalSinceNow)
        let accuracy = location.horizontalAccuracy
        return age <= 10 && accuracy >= 0 && accuracy <= 50
    }
}

struct MockLocationService: LocationService {
    let coordinate: CLLocationCoordinate2D
    let updates: [LocationSample]
    let updateIntervalNanoseconds: UInt64

    init(
        coordinate: CLLocationCoordinate2D = .init(latitude: 34.651562, longitude: 135.591204),
        updates: [LocationSample] = [],
        updateIntervalNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.coordinate = coordinate
        if updates.isEmpty {
            self.updates = [LocationSample(
                coordinate: coordinate,
                altitude: nil,
                horizontalAccuracy: 5,
                verticalAccuracy: nil,
                heading: 0,
                headingAccuracy: 10,
                course: 0,
                timestamp: Date()
            )]
        } else {
            self.updates = updates
        }
        self.updateIntervalNanoseconds = updateIntervalNanoseconds
    }

    func requestWhenInUseAuthorization() async {}

    func currentLocation() async throws -> CLLocationCoordinate2D {
        coordinate
    }

    func locationUpdates() -> AsyncStream<Result<LocationSample, Error>> {
        AsyncStream { continuation in
            Task {
                for sample in updates {
                    continuation.yield(.success(sample))
                    if updateIntervalNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: updateIntervalNanoseconds)
                    }
                }
                continuation.finish()
            }
        }
    }

    func stopLocationUpdates() {}
}
