import Foundation
import OSLog

@MainActor
final class BattleViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case ready
        case inputting
        case resolving
        case result(BattleResult)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var state: BattleState = .mock

    private let sessionID: String
    private let service: BattleService
    private let haptics: HapticsService
    private var lastState: BattleState?
    private var isJoining = false
    private let logger = Logger(subsystem: "RealFightingGame", category: "Battle")

    init(sessionID: String, service: BattleService, haptics: HapticsService = ServiceFactory.makeHapticsService()) {
        self.sessionID = sessionID
        self.service = service
        self.haptics = haptics
    }

    func onAppear() {
        guard !isJoining else { return }
        isJoining = true
        phase = .ready
        haptics.prepare()
        Task { [weak self] in
            guard let self else { return }
            do {
                let s = try await service.join(sessionID: sessionID)
                self.state = s
                self.phase = .inputting
                // 非ターン制: 状態ストリームを購読
                Task { [weak self] in
                    guard let self else { return }
                    let stream = await service.states()
                    for await next in stream {
                        await MainActor.run {
                            // 差分検出
                            let prev = self.lastState
                            self.lastState = next
                            self.state = next

                            // 被弾: 自HPが減少
                            if let prev, next.selfStatus.hp < prev.selfStatus.hp {
                                self.haptics.playerHit()
                            }
                            // Special準備完了: <1.0 → >=1.0 にクロス
                            if let prev, prev.chantProgress < 1.0, next.chantProgress >= 1.0 {
                                self.haptics.specialReady()
                            }

                            if next.opponentStatus.hp <= 0 { self.phase = .result(.win); self.haptics.win() }
                            else if next.selfStatus.hp <= 0 { self.phase = .result(.lose); self.haptics.lose() }
                        }
                    }
                }
            } catch {
                self.logger.error("join failed: \(error.localizedDescription)")
                self.phase = .result(.lose)
            }
        }
    }

    func attackTapped() {
        guard case .inputting = phase else { return }
        haptics.attackTap()
        Task { [service] in await service.send(.attack) }
    }

    func guardTapped() {
        guard case .inputting = phase else { return }
        Task { [service] in await service.send(.guard) }
    }

    func specialTapped() {
        guard case .inputting = phase else { return }
        haptics.specialCast()
        Task { [service] in await service.send(.special) }
    }

    func retry() {
        phase = .idle
        onAppear()
    }

    func onDisappear() {
        Task { [service] in
            await service.end()
        }
        haptics.stop()
    }
}
