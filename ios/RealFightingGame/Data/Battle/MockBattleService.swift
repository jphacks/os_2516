import Foundation

/// ランダム性のある最小のローカル対戦モック。
/// - 役割: MVP期間中の疎通確認とUI/VMの結線。
/// - 特徴: `join`で初期化し、`perform(.attack)`で自→敵の順に解決。
actor MockBattleService: BattleService {
    public struct Config {
        public var latencyMs: UInt64 = 300
        public var playerDamageRange: ClosedRange<Int> = 18...22
        public var enemyDamageRange: ClosedRange<Int> = 10...16
        public var specialDamage: Int = 30
        public var specialChargePerTurn: Double = 0.5

        public init(latencyMs: UInt64 = 300,
                    playerDamageRange: ClosedRange<Int> = 18...22,
                    enemyDamageRange: ClosedRange<Int> = 10...16,
                    specialDamage: Int = 30,
                    specialChargePerTurn: Double = 0.5) {
            self.latencyMs = latencyMs
            self.playerDamageRange = playerDamageRange
            self.enemyDamageRange = enemyDamageRange
            self.specialDamage = specialDamage
            self.specialChargePerTurn = specialChargePerTurn
        }
    }

    private var state: BattleState?
    private let config: Config
    private var guardActive: Bool = false

    init(config: Config = .init()) {
        self.config = config
    }

    // MARK: - BattleService

    func join(sessionID: String) async throws -> BattleState {
        // 初期状態: 双方100HP、モックのテレメトリ
        var initial = BattleState(
            selfStatus: BattleParticipant(displayName: "あなた", hp: 100, maxHp: 100, mana: 50, maxMana: 50),
            opponentStatus: BattleParticipant(displayName: "相手", hp: 100, maxHp: 100, mana: 50, maxMana: 50),
            telemetry: BattleTelemetry(distanceMeters: 10, headingDegrees: 0, lastUpdate: .now),
            chantProgress: 0,
            runEnergy: 0
        )
        // 特殊は開始時点で使用可能にしておく（最小モック）
        initial.chantProgress = 1
        state = initial
        try? await Task.sleep(nanoseconds: config.latencyMs * 1_000_000)
        return initial
    }

    func perform(action: BattleAction) async throws -> BattleState {
        guard var current = state else {
            throw NSError(domain: "MockBattleService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not joined"])
        }

        try? await Task.sleep(nanoseconds: config.latencyMs * 1_000_000)

        switch action {
        case .attack:
            // プレイヤー攻撃
            let playerDmg = Int.random(in: config.playerDamageRange)
            let newEnemyHP = max(0, current.opponentStatus.hp - playerDmg)
            current.opponentStatus = BattleParticipant(
                displayName: current.opponentStatus.displayName,
                hp: newEnemyHP,
                maxHp: current.opponentStatus.maxHp,
                mana: current.opponentStatus.mana,
                maxMana: current.opponentStatus.maxMana
            )

            if current.opponentStatus.hp <= 0 {
                state = current
                return current
            }

            // 敵の反撃
            let enemyDmg = Int.random(in: config.enemyDamageRange)
            let newSelfHP = max(0, current.selfStatus.hp - enemyDmg)
            current.selfStatus = BattleParticipant(
                displayName: current.selfStatus.displayName,
                hp: newSelfHP,
                maxHp: current.selfStatus.maxHp,
                mana: current.selfStatus.mana,
                maxMana: current.selfStatus.maxMana
            )
            // ターン終了処理（ゲージ進行）
            current.chantProgress = min(1, current.chantProgress + config.specialChargePerTurn)
            current.runEnergy = max(0, current.runEnergy - 0.2)
            state = current
            return current

        case .guard:
            // 守りの姿勢：次の被ダメージを半減
            guardActive = true
            current.runEnergy = 1

            // 敵の攻撃のみ（プレイヤーの与ダメなし）
            var enemyDmg = Int.random(in: config.enemyDamageRange)
            if guardActive {
                enemyDmg = Int(ceil(Double(enemyDmg) * 0.5))
            }
            let newSelfHP = max(0, current.selfStatus.hp - enemyDmg)
            current.selfStatus = BattleParticipant(
                displayName: current.selfStatus.displayName,
                hp: newSelfHP,
                maxHp: current.selfStatus.maxHp,
                mana: current.selfStatus.mana,
                maxMana: current.selfStatus.maxMana
            )
            guardActive = false
            // ゲージ調整
            current.chantProgress = min(1, current.chantProgress + 0.3)
            current.runEnergy = 0

            state = current
            return current

        case .special:
            // 特殊攻撃：固定ダメージ。チャージ未満なら攻撃不発（状態は据え置き）
            guard current.chantProgress >= 1 else {
                return current
            }
            let dmg = config.specialDamage
            let newEnemyHP = max(0, current.opponentStatus.hp - dmg)
            current.opponentStatus = BattleParticipant(
                displayName: current.opponentStatus.displayName,
                hp: newEnemyHP,
                maxHp: current.opponentStatus.maxHp,
                mana: current.opponentStatus.mana,
                maxMana: current.opponentStatus.maxMana
            )
            // チャージ消費
            current.chantProgress = 0

            if current.opponentStatus.hp <= 0 {
                state = current
                return current
            }

            // 敵の反撃（通常）
            let enemyDmg2 = Int.random(in: config.enemyDamageRange)
            let newSelfHP2 = max(0, current.selfStatus.hp - enemyDmg2)
            current.selfStatus = BattleParticipant(
                displayName: current.selfStatus.displayName,
                hp: newSelfHP2,
                maxHp: current.selfStatus.maxHp,
                mana: current.selfStatus.mana,
                maxMana: current.selfStatus.maxMana
            )

            state = current
            return current
        }
    }

    func end() async {
        state = nil
    }
}
