import Combine
import CoreLocation
import CoreMotion
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
    @Published private(set) var opponentIndicator: BattleTelemetry? = nil
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var stepRatePerSec: Double? = nil
    @Published private(set) var motionPermissionDenied: Bool = false

    private let sessionID: String
    private let service: BattleService
    private let haptics: HapticsService
    private let audio: AudioService
    private let motionService: MotionService?
    private let locationService: LocationService?
    private var lastState: BattleState?
    private var isJoining = false
    private let logger = Logger(subsystem: "RealFightingGame", category: "Battle")
    private var motionStreamTask: Task<Void, Never>?
    private var manaRegenTask: Task<Void, Never>?
    private var locationStreamTask: Task<Void, Never>?
    private var positionPublisherTask: Task<Void, Never>?
    private var latestLocationSample: LocationSample?
    private var lastPositionSentAt: Date?
    private let positionSendInterval: TimeInterval = 0.5
    private let manaRegenPerSecond: Int = 3
    let attackManaCost: Int = 30

    init(sessionID: String,
         service: BattleService,
         haptics: HapticsService = ServiceFactory.makeHapticsService(),
         audio: AudioService = ServiceFactory.makeAudioService(),
         motionService: MotionService? = nil,
         locationService: LocationService? = nil) {
        self.sessionID = sessionID
        self.service = service
        self.haptics = haptics
        self.audio = audio
        self.motionService = motionService
        self.locationService = locationService
    }

    func onAppear() {
        guard !isJoining else { return }
        isJoining = true
        phase = .ready
        haptics.prepare()
        audio.prepare()
        if locationService != nil { startLocationMonitoring() }
        // 権限状態を確認（.denied/.restricted の場合は案内表示用にフラグを立てる）
        let auth = CMPedometer.authorizationStatus()
        motionPermissionDenied = (auth == .denied || auth == .restricted)

        Task { [weak self] in
            guard let self else { return }
            do {
                let s = try await service.join(sessionID: sessionID)
                self.state = s
                self.phase = .inputting
                Task { [weak self] in
                    guard let self else { return }
                    let stream = await service.states()
                    for await next in stream {
                        await MainActor.run {
                            self.applyRemoteState(next)
                        }
                    }
                }

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
        // Attack時の振動をSpecialと同一に変更
        haptics.specialCast()
        // ファイヤーボールSEを再生
        audio.playMagic(fileName: "fireball_cast.mp3")
        // 楽観的更新: ローカルで即時にMPを消費しUIへ反映
        guard let update = sendPositionUpdateIfNeeded(force: true) else {
            logger.error("[Battle] attack aborted due to missing position")
            return
        }
        haptics.attackTap()
        decreaseMana(by: attackManaCost)
        let context = BattleAttackContext(position: update, attackId: nil, chargeLevel: nil)
        Task { [service] in await service.triggerAttack(with: context) }
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
        audio.stopAll()
        motionStreamTask?.cancel(); motionStreamTask = nil
        manaRegenTask?.cancel(); manaRegenTask = nil
        stepRatePerSec = nil
        motionPermissionDenied = false
        positionPublisherTask?.cancel(); positionPublisherTask = nil
        locationStreamTask?.cancel(); locationStreamTask = nil
        locationService?.stopLocationUpdates()
        latestLocationSample = nil
    }

    // MARK: - Private helpers

    private func applyRemoteState(_ next: BattleState) {
        let prev = lastState
        lastState = next

        // リモート状態とローカルMPを常にクライアント優先でマージ
        let localMana = state.selfStatus.mana
        var merged = next
        merged.selfStatus = BattleParticipant(
            displayName: next.selfStatus.displayName,
            hp: next.selfStatus.hp,
            maxHp: next.selfStatus.maxHp,
            mana: localMana,
            maxMana: next.selfStatus.maxMana
        )
        logger.debug("[Battle] merge mana (client-authoritative) local=\(localMana, privacy: .public) remote=\(next.selfStatus.mana, privacy: .public)")
        state = merged
    // update opponent indicator from telemetry
    opponentIndicator = state.telemetry

        if let prev, next.selfStatus.hp < prev.selfStatus.hp {
            haptics.playerHit()
            audio.play(effect: .hit)
        }
        if let prev, prev.chantProgress < 1.0, next.chantProgress >= 1.0 {
            haptics.specialReady()
        }

        if next.opponentStatus.hp <= 0 {
            if phase != .result(.win) {
                phase = .result(.win)
                haptics.win()
                audio.play(effect: .win)
            }
        } else if next.selfStatus.hp <= 0 {
            if phase != .result(.lose) {
                phase = .result(.lose)
                haptics.lose()
                audio.play(effect: .lose)
            }
        }
    }

    private func startLocationMonitoring() {
        guard locationStreamTask == nil else { return }
        locationStreamTask = Task { [weak self] in
            guard let self else { return }
            await self.locationService?.requestWhenInUseAuthorization()
            guard let updates = self.locationService?.locationUpdates() else { return }
            for await update in updates {
                if Task.isCancelled { break }
                switch update {
                case .success(let sample):
                    await MainActor.run {
                        self.handleLocationSample(sample)
                    }
                case .failure(let error):
                    await MainActor.run {
                        self.logger.error("[Battle] location update error: \(error.localizedDescription)")
                    }
                }
            }
        }
        startPositionPublisher()
    }

    private func handleLocationSample(_ sample: LocationSample) {
        latestLocationSample = sample
        updateTelemetry(with: sample)
    }

    private func startPositionPublisher() {
        guard positionPublisherTask == nil else { return }
        positionPublisherTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.positionSendInterval * 1_000_000_000))
                await MainActor.run {
                    _ = self.sendPositionUpdateIfNeeded(force: false)
                }
            }
        }
    }

    @discardableResult
    private func sendPositionUpdateIfNeeded(force: Bool) -> BattlePositionUpdate? {
        guard let sample = latestLocationSample,
              let update = makePositionUpdate(from: sample) else { return nil }

        let sampleAge = Date().timeIntervalSince(sample.timestamp)
        guard sampleAge <= 5 else {
            logger.debug("[Battle] position skipped due to stale sample age=\(sampleAge)")
            return nil
        }

        if !force, let last = lastPositionSentAt, abs(last.timeIntervalSince(sample.timestamp)) < 0.01 {
            return update
        }

        lastPositionSentAt = sample.timestamp
        Task { [service] in await service.sendPositionUpdate(update) }
        logger.debug("[Battle] position sent heading=\(update.heading, privacy: .public) accuracy=\(update.horizontalAccuracy, privacy: .public)")
        return update
    }

    private func makePositionUpdate(from sample: LocationSample) -> BattlePositionUpdate? {
        let headingSource = sample.heading ?? sample.course
        guard let headingValue = headingSource else { return nil }
        let normalized = normalizeHeading(headingValue)
        return BattlePositionUpdate(
            coordinate: sample.coordinate,
            altitude: sample.altitude,
            horizontalAccuracy: sample.horizontalAccuracy,
            verticalAccuracy: sample.verticalAccuracy,
            heading: normalized,
            headingAccuracy: sample.headingAccuracy,
            timestamp: sample.timestamp
        )
    }

    private func normalizeHeading(_ value: CLLocationDirection) -> CLLocationDirection {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result < 0 { result += 360 }
        return result
    }

    private func updateTelemetry(with sample: LocationSample) {
        guard let heading = sample.heading ?? sample.course else { return }
        let telemetry = BattleTelemetry(
            distanceMeters: state.telemetry.distanceMeters,
            headingDegrees: heading,
            lastUpdate: sample.timestamp
        )
        state = BattleState(
            selfStatus: state.selfStatus,
            opponentStatus: state.opponentStatus,
            telemetry: telemetry,
            chantProgress: state.chantProgress,
            runEnergy: state.runEnergy
        )
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

    private func decreaseMana(by amount: Int) {
        guard amount > 0 else { return }
        var me = state.selfStatus
        let old = me.mana
        let newMana = max(0, me.mana - amount)
        if newMana == me.mana { return }
        let newSelf = BattleParticipant(displayName: me.displayName, hp: me.hp, maxHp: me.maxHp, mana: newMana, maxMana: me.maxMana)
        state = BattleState(selfStatus: newSelf, opponentStatus: state.opponentStatus, telemetry: state.telemetry, chantProgress: state.chantProgress, runEnergy: state.runEnergy)
        logger.debug("[Battle] MP consume -\(amount, privacy: .public) \(old, privacy: .public)->\(newMana, privacy: .public)")
    }
}
