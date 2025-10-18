import Foundation

enum AppConfiguration {
    static let apiBaseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }

        if let infoValue = Bundle.main.infoDictionary?["API_BASE_URL"] as? String,
           let url = URL(string: infoValue) {
            return url
        }

        // TODO: 環境に合わせて適切なAPIエンドポイントを設定してください
        return URL(string: "http://localhost:8080")!
    }()
}
