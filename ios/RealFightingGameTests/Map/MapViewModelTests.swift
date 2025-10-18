import XCTest
import MapKit
@testable import RealFightingGame

final class MapViewModelTests: XCTestCase {

    @MainActor
    func testLoadPins_success() async throws {
        let vm = MapViewModel(service: MockMapService(mode: .success, latencyMs: 0, failureRate: 0, useFixture: false),
                              region: .defaultRegion)
        vm.loadPins()
        try await Task.sleep(nanoseconds: 50_000_000)
        guard case let .success(pins) = vm.pinsState else {
            return XCTFail("期待: success")
        }
        XCTAssertFalse(pins.isEmpty)
        XCTAssertNotNil(vm.userLocationPin)
    }

    @MainActor
    func testLoadPins_empty() async throws {
        let vm = MapViewModel(service: MockMapService(mode: .empty, latencyMs: 0, failureRate: 0),
                              region: .defaultRegion)
        vm.loadPins()
        try await Task.sleep(nanoseconds: 50_000_000)
        if case .empty = vm.pinsState {
            XCTAssertNotNil(vm.userLocationPin)
        } else {
            XCTFail("期待: empty")
        }
    }

    @MainActor
    func testLoadPins_error() async throws {
        let vm = MapViewModel(service: MockMapService(mode: .error, latencyMs: 0, failureRate: 0),
                              region: .defaultRegion)
        vm.loadPins()
        try await Task.sleep(nanoseconds: 50_000_000)
        if case .failure = vm.pinsState {
            XCTAssertNil(vm.userLocationPin)
        } else {
            XCTFail("期待: failure")
        }
    }
}
