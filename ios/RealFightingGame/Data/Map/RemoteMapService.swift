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
        var components = URLComponents(url: baseURL.appendingPathComponent("game"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(region.center.latitude)),
            URLQueryItem(name: "lng", value: String(region.center.longitude))
        ]

        guard let url = components?.url else {
            throw RemoteMapServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw RemoteMapServiceError.invalidResponse
        }

        let payload = try decoder.decode(GameResponse.self, from: data)

        let spots = payload.battleStages.map { stage -> MapPin in
            let coordinate = CLLocationCoordinate2D(latitude: stage.latitude, longitude: stage.longitude)
            let uuid = UUID(uuidString: stage.id) ?? UUID()
            return MapPin(
                id: uuid,
                title: stage.name,
                coordinate: coordinate,
                stageID: stage.id,
                distanceMeters: stage.distanceMeters
            )
        }

        return MapPinsResult(userLocation: nil, spots: spots)
    }
}

extension RemoteMapService {
    enum RemoteMapServiceError: Error {
        case invalidURL
        case invalidResponse
    }

    fileprivate struct GameResponse: Decodable {
        struct BattleStage: Decodable {
            let id: String
            let name: String
            let latitude: Double
            let longitude: Double
            let radiusMeters: Double?
            let description: String?
            let distanceMeters: Double?
        }

        let battleStages: [BattleStage]
        let radiusMeters: Double?
    }
}
