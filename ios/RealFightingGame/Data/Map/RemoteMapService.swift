import Foundation
import MapKit

struct RemoteMapService: MapService {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL,
         session: URLSession = .shared,
         decoder: JSONDecoder = {
             let jsonDecoder = JSONDecoder()
             jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
             return jsonDecoder
         }()) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
    }

    func fetchPins(in region: MKCoordinateRegion) async throws -> MapPinsResult {
        var components = URLComponents(url: baseURL.appendingPathComponent("map/spots"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(region.center.latitude)),
            URLQueryItem(name: "lon", value: String(region.center.longitude)),
            URLQueryItem(name: "radiusMeters", value: String(Int(max(region.span.latitudeDelta, region.span.longitudeDelta) * 111_000)))
        ]

        guard let url = components?.url else {
            throw RemoteMapServiceError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw RemoteMapServiceError.invalidResponse
        }

        let payload = try decoder.decode(MapSpotsResponse.self, from: data)
        let spots = payload.spots.map {
            MapPin(title: $0.name,
                   coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
        }

        let userPin = payload.playerLocation.map {
            MapPin(title: $0.name ?? "現在地",
                   coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
        }

        return MapPinsResult(userLocation: userPin, spots: spots)
    }
}

extension RemoteMapService {
    enum RemoteMapServiceError: Error {
        case invalidURL
        case invalidResponse
    }

    fileprivate struct MapSpotsResponse: Decodable {
        struct Spot: Decodable {
            let id: String?
            let name: String
            let latitude: Double
            let longitude: Double
        }

        struct PlayerLocation: Decodable {
            let latitude: Double
            let longitude: Double
            let name: String?
        }

        let spots: [Spot]
        let playerLocation: PlayerLocation?
    }
}

