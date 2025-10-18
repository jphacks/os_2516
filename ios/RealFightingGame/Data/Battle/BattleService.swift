import Foundation

// MARK: - Domain Models

enum BattleAction: Equatable {
    case attack
    case `guard`
    case special
}

enum BattleResult: Equatable {
    case win
    case lose
}

// MARK: - Service Boundary

protocol BattleService {
    func join(sessionID: String) async throws -> BattleState
    // 段階移行: 非ターン制
    func send(_ action: BattleAction) async
    func states() async -> AsyncStream<BattleState>
    // 互換API（暫定）: send後の最新状態を返す。将来削除想定。
    func perform(action: BattleAction) async throws -> BattleState
    func end() async
}
