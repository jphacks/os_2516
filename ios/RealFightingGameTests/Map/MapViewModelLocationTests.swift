import XCTest
import MapKit
@testable import RealFightingGame

final class MapViewModelLocationTests: XCTestCase {

    @MainActor
    func testRecenterOnUserUsesBackendPinIfAvailable() {
        let backendPin = MapPin(title: "現在地",
                                coordinate: CLLocationCoordinate2D(latitude: 34.6543, longitude: 135.5921))
        let viewModel = MapViewModel(
            service: MockMapService(mode: .empty, latencyMs: 0, failureRate: 0),
            region: .defaultRegion,
            userLocationPin: backendPin
        )

        viewModel.recenterOnUser()

        XCTAssertEqual(viewModel.region.center.latitude, backendPin.coordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(viewModel.region.center.longitude, backendPin.coordinate.longitude, accuracy: 0.0001)
    }

    @MainActor
    func testRecenterOnUserFallsBackToDeviceLocation() async throws {
        let expected = CLLocationCoordinate2D(latitude: 34.6601, longitude: 135.6022)
        let viewModel = MapViewModel(
            service: MockMapService(mode: .empty, latencyMs: 0, failureRate: 0),
            locationService: MockLocationService(coordinate: expected),
            region: .defaultRegion,
            userLocationPin: nil
        )

        viewModel.recenterOnUser()

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.region.center.latitude, expected.latitude, accuracy: 0.0001)
        XCTAssertEqual(viewModel.region.center.longitude, expected.longitude, accuracy: 0.0001)
        XCTAssertNotNil(viewModel.userLocationPin)
    }

    @MainActor
    func testStartTrackingUserLocationUpdatesPin() async throws {
        let updates = [
            CLLocationCoordinate2D(latitude: 34.651562, longitude: 135.591204),
            CLLocationCoordinate2D(latitude: 34.652, longitude: 135.592)
        ]
        let locationService = MockLocationService(coordinate: updates[0],
                                                  updates: updates,
                                                  updateIntervalNanoseconds: 0)
        let viewModel = MapViewModel(
            service: MockMapService(mode: .empty, latencyMs: 0, failureRate: 0),
            locationService: locationService,
            region: .defaultRegion
        )

        viewModel.isFollowingUser = false
        viewModel.startTrackingUserLocation()
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(viewModel.userLocationPin?.coordinate.latitude, updates.last?.latitude)
        XCTAssertEqual(viewModel.userLocationPin?.coordinate.longitude, updates.last?.longitude)

        viewModel.stopTrackingUserLocation()
    }
}
