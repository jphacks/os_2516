import Foundation
import MapKit

enum MockMode {
    case success
    case empty
    case error
}

struct MockMapService: MapService {
    let mode: MockMode
    let latencyMs: UInt64
    let failureRate: Double
    let useFixture: Bool

    init(mode: MockMode = .success, latencyMs: UInt64 = 300, failureRate: Double = 0.0, useFixture: Bool = true) {
        self.mode = mode
        self.latencyMs = latencyMs
        self.failureRate = failureRate
        self.useFixture = useFixture
    }

    func fetchPins(in region: MKCoordinateRegion) async throws -> MapPinsResult {
        // 人工レイテンシ
        try? await Task.sleep(nanoseconds: latencyMs * 1_000_000)

        // 失敗率シミュレーション
        if failureRate > 0, Double.random(in: 0 ... 1) < failureRate {
            throw NSError(domain: "MockMapService", code: -1, userInfo: [NSLocalizedDescriptionKey: "ランダム失敗"])
        }

        let userPin = MapPin(title: "現在地", coordinate: CLLocationCoordinate2D(latitude: 34.651562, longitude: 135.591204))

        switch mode {
        case .error:
            throw NSError(domain: "MockMapService", code: -2, userInfo: [NSLocalizedDescriptionKey: "強制失敗モード"])
        case .empty:
            return MapPinsResult(userLocation: userPin, spots: [])
        case .success:
            let pins: [MapPin]
            if useFixture, let fixturePins = try? FixtureLoader.loadPinsFromBundle() {
                pins = fixturePins
            } else {
                pins = SyntheticPinsGenerator.generate(center: region.center, count: 6, spread: 0.004)
            }
            return MapPinsResult(userLocation: userPin, spots: pins)
        }
    }
}

enum FixtureLoader {
    struct PinDTO: Decodable {
        let title: String
        let latitude: Double
        let longitude: Double
    }

    static func loadPinsFromBundle() throws -> [MapPin] {
        guard let url = Bundle.main.url(forResource: "pins", withExtension: "json") else {
            throw NSError(domain: "FixtureLoader", code: 404, userInfo: [NSLocalizedDescriptionKey: "pins.json が見つかりません"])
        }
        let data = try Data(contentsOf: url)
        let dtos = try JSONDecoder().decode([PinDTO].self, from: data)
        return dtos.map {
            MapPin(title: $0.title, coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
        }
    }
}

enum SyntheticPinsGenerator {
    static func generate(center: CLLocationCoordinate2D, count: Int, spread: CLLocationDegrees) -> [MapPin] {
        (0 ..< count).map { index in
            let offsetLat = Double.random(in: -spread ... spread)
            let offsetLon = Double.random(in: -spread ... spread)
            return MapPin(
                title: "スポット \(index + 1)",
                coordinate: CLLocationCoordinate2D(latitude: center.latitude + offsetLat, longitude: center.longitude + offsetLon)
            )
        }
    }
}
