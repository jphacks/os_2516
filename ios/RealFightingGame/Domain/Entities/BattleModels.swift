import Foundation

struct BattleParticipant: Identifiable {
    let id = UUID()
    let displayName: String
    let hp: Int
    let maxHp: Int
    let mana: Int
    let maxMana: Int
}

struct BattleTelemetry {
    let distanceMeters: Double
    let headingDegrees: Double
    let lastUpdate: Date
}

struct BattleState {
    var selfStatus: BattleParticipant
    var opponentStatus: BattleParticipant
    var telemetry: BattleTelemetry
    var chantProgress: Double
    var runEnergy: Double
}

extension BattleParticipant {
    static let mockSelf = BattleParticipant(displayName: "プレイヤー", hp: 88, maxHp: 100, mana: 50, maxMana: 80)
    static let mockOpponent = BattleParticipant(displayName: "宿敵の妖精", hp: 60, maxHp: 100, mana: 70, maxMana: 90)
}

extension BattleState {
    static let mock = BattleState(
        selfStatus: .mockSelf,
        opponentStatus: .mockOpponent,
        telemetry: .init(distanceMeters: 8.4, headingDegrees: 32, lastUpdate: .now),
        chantProgress: 0.35,
        runEnergy: 0.6
    )
}
