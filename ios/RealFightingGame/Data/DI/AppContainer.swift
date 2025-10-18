import Foundation
import MapKit

final class AppContainer: ObservableObject {
    let mapService: MapService
    let locationService: LocationService

    init(useMock: Bool = AppContainer.defaultUseMock) {
        if useMock {
            self.mapService = MockMapService(mode: .success, latencyMs: 200, failureRate: 0.0, useFixture: true)
            self.locationService = MockLocationService(
                coordinate: CLLocationCoordinate2D(latitude: 34.651562, longitude: 135.591204),
                updates: [
                    CLLocationCoordinate2D(latitude: 34.651562, longitude: 135.591204),
                    CLLocationCoordinate2D(latitude: 34.6521, longitude: 135.592),
                    CLLocationCoordinate2D(latitude: 34.6529, longitude: 135.5928)
                ],
                updateIntervalNanoseconds: 2_000_000_000
            )
        } else {
            self.mapService = MockMapService(mode: .success, latencyMs: 200, failureRate: 0.0, useFixture: true)
            self.locationService = CoreLocationService()
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
