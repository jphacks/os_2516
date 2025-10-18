import Foundation

struct AuthSession: Codable {
    let token: String
    let expiryDate: Date
    let user: UserProfile

    var isExpired: Bool {
        Date() >= expiryDate
    }
}

actor AuthSessionStore {
    private let storageKey = "auth.session"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ session: AuthSession) throws {
        let data = try encoder.encode(session)
        defaults.set(data, forKey: storageKey)
    }

    func load() -> AuthSession? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }

        return try? decoder.decode(AuthSession.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}
