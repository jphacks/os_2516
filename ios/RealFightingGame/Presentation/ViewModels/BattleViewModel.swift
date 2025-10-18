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
    private var isJoining = false
    private let logger = Logger(subsystem: "RealFightingGame", category: "Battle")

    init(sessionID: String, service: BattleService) {
        self.sessionID = sessionID
        self.service = service
    }

    func onAppear() {
        guard !isJoining else { return }
        isJoining = true
        phase = .ready
        Task { [weak self] in
            guard let self else { return }
            do {
                let s = try await service.join(sessionID: sessionID)
                self.state = s
                self.phase = .inputting
            } catch {
                self.logger.error("join failed: \(error.localizedDescription)")
                self.phase = .result(.lose) // 最小実装: 失敗時は敗北扱い
            }
        }
    }

    func attackTapped() {
        guard case .inputting = phase else { return }
        phase = .resolving
        Task { [weak self] in
            guard let self else { return }
            do {
                let s = try await service.perform(action: BattleAction.attack)
                self.state = s

                if s.opponentStatus.hp <= 0 {
                    self.phase = .result(.win)
                } else if s.selfStatus.hp <= 0 {
                    self.phase = .result(.lose)
                } else {
                    self.phase = .inputting
                }
            } catch {
                self.logger.error("perform failed: \(error.localizedDescription)")
                self.phase = .inputting
            }
        }
    }

    func guardTapped() {
        guard case .inputting = phase else { return }
        phase = .resolving
        Task { [weak self] in
            guard let self else { return }
            do {
                let s = try await service.perform(action: BattleAction.guard)
                self.state = s
                if s.selfStatus.hp <= 0 { self.phase = .result(.lose) }
                else if s.opponentStatus.hp <= 0 { self.phase = .result(.win) }
                else { self.phase = .inputting }
            } catch {
                self.logger.error("perform failed: \(error.localizedDescription)")
                self.phase = .inputting
            }
        }
    }

    func specialTapped() {
        guard case .inputting = phase else { return }
        // ボタン側でチャージ不足は無効化するが、念のため
        phase = .resolving
        Task { [weak self] in
            guard let self else { return }
            do {
                let s = try await service.perform(action: BattleAction.special)
                self.state = s
                if s.opponentStatus.hp <= 0 { self.phase = .result(.win) }
                else if s.selfStatus.hp <= 0 { self.phase = .result(.lose) }
                else { self.phase = .inputting }
            } catch {
                self.logger.error("perform failed: \(error.localizedDescription)")
                self.phase = .inputting
            }
        }
    }

    func retry() {
        phase = .idle
        onAppear()
    }

    func onDisappear() {
        Task { [service] in
            await service.end()
        }
    }
}
