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
}
