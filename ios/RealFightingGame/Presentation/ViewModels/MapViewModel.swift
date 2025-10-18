import Combine
import Foundation
import MapKit

@MainActor
final class MapViewModel: ObservableObject {
    @Published var region: MKCoordinateRegion
    @Published private(set) var pinsState: ViewState<[MapPin]> = .idle
    @Published var userLocationPin: MapPin?
    @Published var isFollowingUser = true

    private let service: MapService
    private let locationService: LocationService?
    private var loadTask: Task<Void, Never>?
    private var locationStreamTask: Task<Void, Never>?
    private var regionDebounceTask: Task<Void, Never>?
    private var isApplyingProgrammaticRegionChange = false

    init(service: MapService,
         locationService: LocationService? = nil,
         region: MKCoordinateRegion = .defaultRegion,
         initialPins: [MapPin] = [],
         userLocationPin: MapPin? = nil) {
        self.service = service
        self.locationService = locationService
        self.region = region
        self.userLocationPin = userLocationPin
        if initialPins.isEmpty {
            pinsState = .idle
        } else {
            pinsState = .success(initialPins)
        }
    }

    deinit {
        loadTask?.cancel()
        locationStreamTask?.cancel()
        regionDebounceTask?.cancel()
    }

    func loadPins(force: Bool = false) {
        if case .loading = pinsState { return }
        if case .success = pinsState, !force { /* keep current */ }

        loadTask?.cancel()
        pinsState = .loading
        loadTask = Task { [region] in
            do {
                let result = try await service.fetchPins(in: region)
                guard !Task.isCancelled else { return }
                if let userPin = result.userLocation, locationService == nil {
                    self.userLocationPin = userPin
                }
                if result.spots.isEmpty {
                    self.pinsState = .empty
                } else {
                    self.pinsState = .success(result.spots)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.pinsState = .failure(error)
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
                        // フォロー状態でも自動リセンターしない
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
            loadPins(force: true)
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
            self.loadPins(force: true)
        }
    }

    func userDidPanMap() {
        isFollowingUser = false
    }

    func handleRegionChangeFromMap(_ newRegion: MKCoordinateRegion) {
        region = newRegion
        if !isApplyingProgrammaticRegionChange {
            userDidPanMap()
            scheduleRegionDebounceLoad()
        }
    }

    private func setRegion(_ coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        isApplyingProgrammaticRegionChange = true
        region = MKCoordinateRegion(center: coordinate, span: span)
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingProgrammaticRegionChange = false
        }
    }

    private func scheduleRegionDebounceLoad() {
        regionDebounceTask?.cancel()
        regionDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }
            await MainActor.run {
                self.loadPins()
            }
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
