import Foundation

enum NearbyInteractionEvent: Equatable {
    case peerToken(String)
    case cleared
    case error(String)
}

struct NearbyInteractionEnvelope: Codable {
    let playerId: String
    let token: String
}
