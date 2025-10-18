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
    private let motionService: MotionService?
    private var lastState: BattleState?
    private var isJoining = false
    private let logger = Logger(subsystem: "RealFightingGame", category: "Battle")
    private var motionStreamTask: Task<Void, Never>?
    private var manaRegenTask: Task<Void, Never>?
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var stepRatePerSec: Double? = nil
    private let manaRegenPerSecond: Int = 3
    let attackManaCost: Int = 5

    init(sessionID: String, service: BattleService, haptics: HapticsService = ServiceFactory.makeHapticsService(), motionService: MotionService? = nil) {
        self.sessionID = sessionID
        self.service = service
        self.haptics = haptics
        self.motionService = motionService
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

                            // リモート状態とローカル回復MPをマージ（上書き防止）
                            let localMana = self.state.selfStatus.mana
                            var merged = next
                            if localMana > next.selfStatus.mana {
                                merged.selfStatus = BattleParticipant(
                                    displayName: next.selfStatus.displayName,
                                    hp: next.selfStatus.hp,
                                    maxHp: next.selfStatus.maxHp,
                                    mana: localMana,
                                    maxMana: next.selfStatus.maxMana
                                )
                                self.logger.debug("[Battle] merge mana local=\(localMana, privacy: .public) remote=\(next.selfStatus.mana, privacy: .public) -> \(merged.selfStatus.mana, privacy: .public)")
                            }
                            self.state = merged

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

                // モーション購読（スパイク: 走行中はMP回復）
                if let motionService = self.motionService {
                    self.motionStreamTask = Task { [weak self] in
                        guard let self else { return }
                        for await update in motionService.updates() {
                            await MainActor.run {
                                self.isRunning = update.isRunning
                                self.stepRatePerSec = update.stepRatePerSec
                                self.logger.debug("[Motion RX] isRunning=\(self.isRunning, privacy: .public), stepRate=\(self.stepRatePerSec ?? -1, privacy: .public)")
                                self.updateManaRegenLoop(running: update.isRunning)
                            }
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
        guard case .inputting = phase, state.selfStatus.mana >= attackManaCost else { return }
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
        motionStreamTask?.cancel(); motionStreamTask = nil
        manaRegenTask?.cancel(); manaRegenTask = nil
        stepRatePerSec = nil
    }

    private func updateManaRegenLoop(running: Bool) {
        if running {
            if manaRegenTask == nil {
                manaRegenTask = Task { [weak self] in
                    while let self, !Task.isCancelled, self.isRunning {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        await MainActor.run { [weak self] in self?.increaseMana(by: self?.manaRegenPerSecond ?? 0) }
                    }
                }
            }
        } else {
            manaRegenTask?.cancel()
            manaRegenTask = nil
        }
    }

    private func increaseMana(by amount: Int) {
        guard amount > 0 else { return }
        var me = state.selfStatus
        let old = me.mana
        let newMana = min(me.maxMana, me.mana + amount)
        if newMana == me.mana { return }
        let newSelf = BattleParticipant(displayName: me.displayName, hp: me.hp, maxHp: me.maxHp, mana: newMana, maxMana: me.maxMana)
        state = BattleState(selfStatus: newSelf, opponentStatus: state.opponentStatus, telemetry: state.telemetry, chantProgress: state.chantProgress, runEnergy: state.runEnergy)
        logger.debug("[Battle] MP regen +\(amount, privacy: .public) \(old, privacy: .public)->\(newMana, privacy: .public)")
    }
}
