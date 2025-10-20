import CoreLocation
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

struct BattlePositionUpdate {
    let coordinate: CLLocationCoordinate2D
    let altitude: CLLocationDistance?
    let horizontalAccuracy: CLLocationAccuracy
    let verticalAccuracy: CLLocationAccuracy?
    let heading: CLLocationDirection
    let headingAccuracy: CLLocationDirection?
    let timestamp: Date
}

struct BattleAttackContext {
    let position: BattlePositionUpdate
    let attackId: UUID?
    let chargeLevel: Int?
}

// MARK: - Service Boundary

protocol BattleService {
    func join(sessionID: String) async throws -> BattleState
    /// 非ターン制: サーバーへアクションを送信
    func send(_ action: BattleAction) async
    func states() async -> AsyncStream<BattleState>
    /// レガシー互換: send 後に最新状態を返す（将来削除予定）
    func perform(action: BattleAction) async throws -> BattleState
    func end() async
    /// 現在地・方位の同期
    func sendPositionUpdate(_ update: BattlePositionUpdate) async
    /// 攻撃トリガーを座標付きで送信
    func triggerAttack(with context: BattleAttackContext) async
    // optional: return the current active session id if available
    func currentSessionId() async -> String?

    // optional: return a known opponent id if available
    func knownOpponentId() async -> String?
}

extension BattleService {
    func sendPositionUpdate(_ update: BattlePositionUpdate) async {}

    func triggerAttack(with context: BattleAttackContext) async {
        await send(.attack)
    }

    // optional defaults: concrete services should override these if they provide session/opponent info
    func currentSessionId() async -> String? { nil }

    func knownOpponentId() async -> String? { nil }
}
