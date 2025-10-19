import Foundation
import MapKit

final class AppContainer: ObservableObject {
    let mapService: MapService
    let locationService: LocationService
    let motionService: MotionService
    let apiBaseURL: URL
    let useMock: Bool

    init(useMock: Bool = AppContainer.defaultUseMock) {
        self.useMock = useMock
        self.apiBaseURL = AppConfiguration.apiBaseURL
        if useMock {
            self.mapService = MockMapService(mode: .success, latencyMs: 200, failureRate: 0.0, useFixture: true)
            let baseCoordinate = CLLocationCoordinate2D(latitude: 34.651562, longitude: 135.591204)
            let route: [CLLocationCoordinate2D] = [
                baseCoordinate,
                CLLocationCoordinate2D(latitude: 34.6521, longitude: 135.592),
                CLLocationCoordinate2D(latitude: 34.6529, longitude: 135.5928)
            ]
            let now = Date()
            let samples: [LocationSample] = route.enumerated().map { index, coordinate in
                LocationSample(
                    coordinate: coordinate,
                    altitude: nil,
                    horizontalAccuracy: 5,
                    verticalAccuracy: nil,
                    heading: 45,
                    headingAccuracy: 15,
                    course: 45,
                    timestamp: now.addingTimeInterval(Double(index))
                )
            }
            self.locationService = MockLocationService(
                coordinate: baseCoordinate,
                updates: samples,
                updateIntervalNanoseconds: 2_000_000_000
            )
            self.motionService = MockMotionService(
                runningPattern: [false, true, true, true, false],
                intervalNanoseconds: 1_000_000_000,
                runningStepRate: 2.8,
                walkingStepRate: 1.2,
                repeats: true
            )
        } else {
            self.mapService = RemoteMapService(baseURL: apiBaseURL)
            self.locationService = CoreLocationService()
            self.motionService = CoreMotionMotionService()
        }
    }

    private static var defaultUseMock: Bool {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment["USE_MOCK"]
        return env == "1"
        #else
        return false
        #endif
    }
}
