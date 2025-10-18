import CoreLocation
import Foundation
import MapKit

@MainActor
final class StageListViewModel: ObservableObject {
    @Published private(set) var stages: [StageListItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let mapService: MapService
    private let locationService: LocationService?
    private var hasLoadedOnce = false

    init(mapService: MapService, locationService: LocationService?) {
        self.mapService = mapService
        self.locationService = locationService
    }

    func loadInitialIfNeeded() async {
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true
        await loadStages()
    }

    func refresh() async {
        await loadStages()
    }

    private func loadStages() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let userCoordinate = await fetchUserCoordinate()
        let region = userCoordinate.map { coordinate in
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        } ?? .defaultRegion

        do {
            let result = try await mapService.fetchPins(in: region)
            let referenceCoordinate = userCoordinate ?? result.userLocation?.coordinate
            let items = result.spots.map { pin -> StageListItem in
                let distance = StageListViewModel.distance(from: referenceCoordinate, to: pin.coordinate) ?? pin.distanceMeters
                return StageListItem(id: pin.id, stageID: pin.stageID, title: pin.title, coordinate: pin.coordinate, distanceMeters: distance)
            }

            stages = items.sorted(by: StageListItem.sortPredicate)
        } catch {
            errorMessage = "ステージ情報を取得できませんでした"
            stages = []
        }
    }

    private func fetchUserCoordinate() async -> CLLocationCoordinate2D? {
        guard let locationService else { return nil }
        await locationService.requestWhenInUseAuthorization()
        return try? await locationService.currentLocation()
    }

    private static func distance(from origin: CLLocationCoordinate2D?, to destination: CLLocationCoordinate2D) -> Double? {
        guard let origin else { return nil }
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return originLocation.distance(from: destinationLocation)
    }
}

struct StageListItem: Identifiable {
    let id: UUID
    let stageID: String?
    let title: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double?

    var distanceText: String? {
        guard let distanceMeters else { return nil }
        if distanceMeters < 1000 {
            return "約" + String(format: "%.0f", distanceMeters) + "m"
        }
        return "約" + String(format: "%.1f", distanceMeters / 1000) + "km"
    }

    static func sortPredicate(_ lhs: StageListItem, _ rhs: StageListItem) -> Bool {
        switch (lhs.distanceMeters, rhs.distanceMeters) {
        case let (lhsDistance?, rhsDistance?):
            return lhsDistance < rhsDistance
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            return lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }
    }
}
