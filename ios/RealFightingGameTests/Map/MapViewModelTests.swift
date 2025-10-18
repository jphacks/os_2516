import XCTest
import MapKit
@testable import RealFightingGame

final class MapViewModelTests: XCTestCase {

    @MainActor
    func testRefreshPins_success() async throws {
        let vm = MapViewModel(service: MockMapService(mode: .success, latencyMs: 0, failureRate: 0, useFixture: false),
                              region: .defaultRegion)
        vm.refreshPins()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(vm.destinations.isEmpty)
        XCTAssertNotNil(vm.userLocationPin)
    }

    @MainActor
    func testRefreshPins_empty() async throws {
        let vm = MapViewModel(service: MockMapService(mode: .empty, latencyMs: 0, failureRate: 0),
                              region: .defaultRegion)
        vm.refreshPins()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(vm.destinations.isEmpty)
        XCTAssertNotNil(vm.userLocationPin)
    }

    @MainActor
    func testRefreshPins_error() async throws {
        let vm = MapViewModel(service: MockMapService(mode: .error, latencyMs: 0, failureRate: 0),
                              region: .defaultRegion)
        vm.refreshPins()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(vm.destinations.isEmpty)
        XCTAssertNil(vm.userLocationPin)
    }
}
