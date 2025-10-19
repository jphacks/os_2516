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
        public var attackManaCost: Int = 5

        public init(latencyMs: UInt64 = 300,
                    playerDamageRange: ClosedRange<Int> = 18...22,
                    enemyDamageRange: ClosedRange<Int> = 10...16,
                    specialDamage: Int = 30,
                    specialChargePerTurn: Double = 0.5,
                    attackManaCost: Int = 5) {
            self.latencyMs = latencyMs
            self.playerDamageRange = playerDamageRange
            self.enemyDamageRange = enemyDamageRange
            self.specialDamage = specialDamage
            self.specialChargePerTurn = specialChargePerTurn
            self.attackManaCost = attackManaCost
        }
    }

    private var state: BattleState?
    private let config: Config
    private var guardActive: Bool = false
    private var guardRemaining: Double = 0 // seconds
    private var enemyCooldown: Double = 0 // seconds
    private var streamCont: AsyncStream<BattleState>.Continuation?
    private var streamCache: AsyncStream<BattleState>?
    private var tickTask: Task<Void, Never>?
    private var pendingActions: [BattleAction] = []

    init(config: Config = .init()) {
        self.config = config
    }

    // MARK: - BattleService

    func join(sessionID: String) async throws -> BattleState {
        // 初期状態: 双方100HP、モックのテレメトリ
        var initial = BattleState(
            selfStatus: BattleParticipant(displayName: "あなた", hp: 100, maxHp: 100, mana: 10, maxMana: 50),
            opponentStatus: BattleParticipant(displayName: "相手", hp: 100, maxHp: 100, mana: 50, maxMana: 50),
            telemetry: BattleTelemetry(distanceMeters: 10, headingDegrees: 0, lastUpdate: .now),
            chantProgress: 0,
            runEnergy: 0
        )
        // 特殊は開始時点で使用可能にしておく（最小モック）
        initial.chantProgress = 1
        state = initial
        startTickIfNeeded()
        try? await Task.sleep(nanoseconds: config.latencyMs * 1_000_000)
        publish()
        return initial
    }

    func perform(action: BattleAction) async throws -> BattleState {
        // 互換API: sendして即時スナップショットを返す
        await send(action)
        return state!
    }

    func send(_ action: BattleAction) async {
        pendingActions.append(action)
    }

    func states() async -> AsyncStream<BattleState> {
        if let s = streamCache { return s }
        let stream = AsyncStream<BattleState> { cont in
            Task { [weak self] in
                await self?.setContinuation(cont)
            }
        }
        streamCache = stream
        return stream
    }

    private func setContinuation(_ cont: AsyncStream<BattleState>.Continuation) {
        streamCont = cont
        if let s = state { cont.yield(s) }
    }

    private func publish() {
        if let s = state { streamCont?.yield(s) }
    }

    private func startTickIfNeeded() {
        guard tickTask == nil else { return }
        let interval: Double = 0.2 // seconds
        tickTask = Task { [weak self] in
            guard let self else { return }
            while true {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await self.tick(delta: interval)
            }
        }
    }

    private func tick(delta: Double) async {
        guard var current = state, current.selfStatus.hp > 0, current.opponentStatus.hp > 0 else { return }

        // 自然回復・減衰
        current.chantProgress = min(1, current.chantProgress + config.specialChargePerTurn * delta) // 約0.5/秒ベース
        if guardRemaining > 0 {
            guardRemaining = max(0, guardRemaining - delta)
            current.runEnergy = max(0, min(1, guardRemaining / 1.5))
        } else {
            current.runEnergy = 0
        }

        // プレイヤー入力処理（非同期に蓄積されたものを消費）
        if !pendingActions.isEmpty {
            for action in pendingActions {
                switch action {
                case .attack:
                    // MP不足なら攻撃は不発（何もしない）
                    guard current.selfStatus.mana >= config.attackManaCost else { continue }
                    // MP消費
                    current.selfStatus = BattleParticipant(
                        displayName: current.selfStatus.displayName,
                        hp: current.selfStatus.hp,
                        maxHp: current.selfStatus.maxHp,
                        mana: max(0, current.selfStatus.mana - config.attackManaCost),
                        maxMana: current.selfStatus.maxMana
                    )
                    let dmg = Int.random(in: config.playerDamageRange)
                    let newEnemyHP = max(0, current.opponentStatus.hp - dmg)
                    current.opponentStatus = BattleParticipant(
                        displayName: current.opponentStatus.displayName,
                        hp: newEnemyHP,
                        maxHp: current.opponentStatus.maxHp,
                        mana: current.opponentStatus.mana,
                        maxMana: current.opponentStatus.maxMana
                    )
                case .guard:
                    guardActive = true
                    guardRemaining = 1.5 // 1.5秒の防御有効時間
                    current.runEnergy = 1
                case .special:
                    if current.chantProgress >= 1 {
                        let newEnemyHP = max(0, current.opponentStatus.hp - config.specialDamage)
                        current.opponentStatus = BattleParticipant(
                            displayName: current.opponentStatus.displayName,
                            hp: newEnemyHP,
                            maxHp: current.opponentStatus.maxHp,
                            mana: current.opponentStatus.mana,
                            maxMana: current.opponentStatus.maxMana
                        )
                        current.chantProgress = 0
                    }
                }
            }
            pendingActions.removeAll(keepingCapacity: true)
        }

        // 敵AI（クールダウンで周期攻撃）
        if enemyCooldown > 0 { enemyCooldown = max(0, enemyCooldown - delta) }
        if enemyCooldown == 0 && current.opponentStatus.hp > 0 {
            var enemyDmg = Int.random(in: config.enemyDamageRange)
            if guardActive || guardRemaining > 0 { enemyDmg = Int(ceil(Double(enemyDmg) * 0.5)) }
            let newSelfHP = max(0, current.selfStatus.hp - enemyDmg)
            current.selfStatus = BattleParticipant(
                displayName: current.selfStatus.displayName,
                hp: newSelfHP,
                maxHp: current.selfStatus.maxHp,
                mana: current.selfStatus.mana,
                maxMana: current.selfStatus.maxMana
            )
            enemyCooldown = 1.2
            guardActive = false // 一撃軽減を消費
        }

        state = current
        publish()
    }

    func end() async {
        state = nil
        streamCont?.finish()
        streamCont = nil
        streamCache = nil
        tickTask?.cancel()
        tickTask = nil
    }
}
