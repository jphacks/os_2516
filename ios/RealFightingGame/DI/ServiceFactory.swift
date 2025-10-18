import Foundation

enum ServiceFactory {
    static func makeBattleService() -> BattleService {
        let useMockEnv = ProcessInfo.processInfo.environment["USE_MOCK"] == "1"
#if DEBUG
        // Debugは既定でモック。環境変数でも強制可能。
        return MockBattleService()
#else
        // Releaseでも USE_MOCK=1 があればモックを利用。
        if useMockEnv {
            return MockBattleService()
        }
        // TODO: 実装後に本番用サービスへ差し替え。
        return MockBattleService()
#endif
    }
}

