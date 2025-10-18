import CoreLocation
import Foundation
import MapKit

@MainActor
final class BattleStageListViewModel: ObservableObject {
    struct Stage: Identifiable, Hashable {
        let id: String
        let name: String
        let coordinate: CLLocationCoordinate2D
        let distanceMeters: Double?
        
        static func == (lhs: Stage, rhs: Stage) -> Bool {
            lhs.id == rhs.id &&
                lhs.name == rhs.name &&
                lhs.coordinate.latitude == rhs.coordinate.latitude &&
                lhs.coordinate.longitude == rhs.coordinate.longitude &&
                lhs.distanceMeters == rhs.distanceMeters
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(name)
            hasher.combine(coordinate.latitude)
            hasher.combine(coordinate.longitude)
            hasher.combine(distanceMeters)
        }
    }

    @Published private(set) var stagesState: ViewState<[Stage]> = .idle

    private let mapService: MapService
    private let locationService: LocationService?
    private var loadTask: Task<Void, Never>?

    init(mapService: MapService, locationService: LocationService?) {
        self.mapService = mapService
        self.locationService = locationService
    }

    deinit {
        loadTask?.cancel()
    }

    func loadStages(force: Bool = false) {
        if !force {
            switch stagesState {
            case .loading:
                return
            case .success where !force:
                return
            default:
                break
            }
        }

        loadTask?.cancel()
        stagesState = .loading

        loadTask = Task { [weak self] in
            guard let self else { return }

            var region = MKCoordinateRegion.defaultRegion
            var userCoordinate: CLLocationCoordinate2D?

            if let locationService {
                await locationService.requestWhenInUseAuthorization()
                if let coordinate = try? await locationService.currentLocation() {
                    userCoordinate = coordinate
                    region = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                }
            }

            do {
                let result = try await mapService.fetchPins(in: region)
                if userCoordinate == nil {
                    userCoordinate = result.userLocation?.coordinate
                }

                let stages = result.spots.compactMap { pin -> Stage? in
                    let identifier = pin.sourceID ?? pin.title.nonEmpty ?? UUID().uuidString
                    let distance = userCoordinate.map { coord in
                        CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                            .distance(from: CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude))
                    }
                    return Stage(id: identifier,
                                 name: pin.title,
                                 coordinate: pin.coordinate,
                                 distanceMeters: distance)
                }

                guard !Task.isCancelled else { return }

                if stages.isEmpty {
                    stagesState = .empty
                } else {
                    stagesState = .success(stages.sorted { lhs, rhs in
                        switch (lhs.distanceMeters, rhs.distanceMeters) {
                        case let (l?, r?):
                            return l < r
                        case (.none, .some):
                            return false
                        case (.some, .none):
                            return true
                        case (.none, .none):
                            return lhs.name < rhs.name
                        }
                    })
                }
            } catch {
                guard !Task.isCancelled else { return }
                stagesState = .failure(error)
            }
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
