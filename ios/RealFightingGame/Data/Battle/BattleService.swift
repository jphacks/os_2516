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
    func perform(action: BattleAction) async throws -> BattleState
    func end() async
}
