import Foundation

struct UserProfile: Identifiable, Codable {
    let id: UUID
    let email: String
    let fullName: String
}
