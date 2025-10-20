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

        // デフォルトは本番APIエンドポイントを直接参照する
        return URL(string: "https://api-server-215122107853.asia-northeast1.run.app/")!
    }()

    static let useMockServices: Bool = {
        if let override = ProcessInfo.processInfo.environment["USE_MOCK"] {
            return override == "1" || override.lowercased() == "true"
        }

        if let infoValue = Bundle.main.infoDictionary?["USE_MOCK"] as? String {
            return infoValue == "1" || infoValue.lowercased() == "true"
        }

        return false
    }()
}
