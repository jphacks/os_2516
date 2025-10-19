import Foundation

enum ServiceFactory {
    static func makeBattleService() -> BattleService {
        if AppConfiguration.useMockServices {
            return MockBattleService()
        }

        // NOTE: アクセストークンが無い状況向けのフォールバックとしてモックを返す。
        // 実際の対戦時は `RemoteBattleService` を直接生成してください。
        return MockBattleService()
    }
}
