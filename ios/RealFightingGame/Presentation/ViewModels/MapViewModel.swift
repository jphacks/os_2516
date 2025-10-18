import Combine
import Foundation
import MapKit

@MainActor
final class MapViewModel: ObservableObject {
    @Published var region: MKCoordinateRegion
    @Published var destinations: [MapPin]

    init(region: MKCoordinateRegion = .defaultRegion,
         destinations: [MapPin] = MapPin.mockPins) {
        self.region = region
        self.destinations = destinations
    }
}

struct MapPin: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: MapPin, rhs: MapPin) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static let mockPins: [MapPin] = [
        MapPin(title: "近畿大学", coordinate: CLLocationCoordinate2D(latitude: 34.651562, longitude: 135.591204)),
        MapPin(title: "魔素が濃い公園", coordinate: CLLocationCoordinate2D(latitude: 35.669, longitude: 139.702)),
        MapPin(title: "訓練フィールド", coordinate: CLLocationCoordinate2D(latitude: 35.6895, longitude: 139.6917))
    ]
}

extension MKCoordinateRegion {
    static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.651562, longitude: 135.591204),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
}
