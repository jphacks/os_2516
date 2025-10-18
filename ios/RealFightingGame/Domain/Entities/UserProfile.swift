import Foundation

struct UserProfile: Identifiable, Codable {
    let id: UUID
    let email: String
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
    }
}
