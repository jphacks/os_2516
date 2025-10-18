import Combine
import Foundation

@MainActor
final class BattleViewModel: ObservableObject {
    @Published private(set) var state: BattleState

    init(state: BattleState = .mock) {
        self.state = state
    }

    func simulateTick() {
        // 今後のイベント更新用ダミー。とりあえずループ用に残しておきます。
        state.telemetry = BattleTelemetry(
            distanceMeters: state.telemetry.distanceMeters,
            headingDegrees: state.telemetry.headingDegrees,
            lastUpdate: .now
        )
    }
}
