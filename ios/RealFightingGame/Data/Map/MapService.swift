import Foundation
import MapKit

struct MapPinsResult {
    let userLocation: MapPin?
    let spots: [MapPin]
}

protocol MapService {
    func fetchPins(in region: MKCoordinateRegion) async throws -> MapPinsResult
}
