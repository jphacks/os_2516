import Combine
import Foundation
import MapKit

@MainActor
final class MapViewModel: ObservableObject {
    @Published var region: MKCoordinateRegion
    @Published var destinations: [MapPin]
    @Published var userLocationPin: MapPin?
    @Published var isFollowingUser = true

    private let service: MapService
    private let locationService: LocationService?
    private var loadTask: Task<Void, Never>?
    private var locationStreamTask: Task<Void, Never>?
    private var isApplyingProgrammaticRegionChange = false

    init(service: MapService,
         locationService: LocationService? = nil,
         region: MKCoordinateRegion = .defaultRegion,
         destinations: [MapPin] = [],
         userLocationPin: MapPin? = nil) {
        self.service = service
        self.locationService = locationService
        self.region = region
        self.destinations = destinations
        self.userLocationPin = userLocationPin
    }

    func refreshPins() {
        loadTask?.cancel()
        loadTask = Task { [region] in
            do {
                let result = try await service.fetchPins(in: region)
                guard !Task.isCancelled else { return }
                self.destinations = result.spots
                if locationService == nil, let userPin = result.userLocation {
                    self.userLocationPin = userPin
                    if self.isFollowingUser {
                        self.setRegion(userPin.coordinate, span: self.region.span)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.destinations = [] // M0は簡易に空へフォールバック
                if locationService == nil {
                    self.userLocationPin = nil
                }
            }
        }
    }

    func startTrackingUserLocation() {
        guard locationStreamTask == nil else { return }

        locationStreamTask = Task { [weak self] in
            guard let self else { return }
            await locationService?.requestWhenInUseAuthorization()

            guard let updates = locationService?.locationUpdates() else { return }

            for await update in updates {
                if Task.isCancelled { break }
                switch update {
                case .success(let coordinate):
                    await MainActor.run {
                        let pin = MapPin(title: "現在地", coordinate: coordinate)
                        self.userLocationPin = pin
                        if self.isFollowingUser {
                            self.setRegion(
                                coordinate,
                                span: MKCoordinateSpan(
                                    latitudeDelta: max(0.008, self.region.span.latitudeDelta),
                                    longitudeDelta: max(0.008, self.region.span.longitudeDelta)
                                )
                            )
                        }
                    }
                case .failure:
                    continue
                }
            }
        }
    }

    func stopTrackingUserLocation() {
        locationStreamTask?.cancel()
        locationStreamTask = nil
        locationService?.stopLocationUpdates()
    }

    func recenterOnUser() {
        isFollowingUser = true
        if let coordinate = userLocationPin?.coordinate {
            setRegion(
                coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: max(0.008, region.span.latitudeDelta),
                    longitudeDelta: max(0.008, region.span.longitudeDelta)
                )
            )
            return
        }

        guard let service = locationService else { return }

        Task { [weak self] in
            guard let self else { return }
            await service.requestWhenInUseAuthorization()
            guard let coordinate = try? await service.currentLocation() else { return }
            self.userLocationPin = MapPin(title: "現在地", coordinate: coordinate)
            self.setRegion(
                coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: max(0.008, self.region.span.latitudeDelta),
                    longitudeDelta: max(0.008, self.region.span.longitudeDelta)
                )
            )
        }
    }

    func userDidPanMap() {
        guard locationService != nil else { return }
        isFollowingUser = false
    }

    func handleRegionChangeFromMap(_ newRegion: MKCoordinateRegion) {
        region = newRegion
        if !isApplyingProgrammaticRegionChange {
            userDidPanMap()
        }
    }

    private func setRegion(_ coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        isApplyingProgrammaticRegionChange = true
        region = MKCoordinateRegion(center: coordinate, span: span)
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingProgrammaticRegionChange = false
        }
    }
}

struct MapPin: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: MapPin, rhs: MapPin) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static let mockPins: [MapPin] = [
        MapPin(title: "近畿大学 正門", coordinate: CLLocationCoordinate2D(latitude: 34.651562, longitude: 135.591204)),
        MapPin(title: "近畿大学 東門", coordinate: CLLocationCoordinate2D(latitude: 34.653189, longitude: 135.594239)),
        MapPin(title: "近畿大学 記念公園", coordinate: CLLocationCoordinate2D(latitude: 34.648872, longitude: 135.588745))
    ]
}

extension MKCoordinateRegion {
    static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.651562, longitude: 135.591204),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
}
