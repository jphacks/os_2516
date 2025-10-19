import Combine
import Foundation
import OSLog
import CoreMotion

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
    @Published private(set) var nearbyStatus: NearbyInteractionService.Status = .idle
    @Published private(set) var nearbyReading: NearbyInteractionService.Reading?
    @Published private(set) var nearbyErrorMessage: String?

    private let sessionID: String
    private let service: BattleService
    private let haptics: HapticsService
    private let audio: AudioService
    private let motionService: MotionService?
    private let nearbyInteraction: NearbyInteractionService?
    private var lastState: BattleState?
    private var isJoining = false
    private let logger = Logger(subsystem: "RealFightingGame", category: "Battle")
    private var motionStreamTask: Task<Void, Never>?
    private var manaRegenTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var nearbyEventsTask: Task<Void, Never>?
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var stepRatePerSec: Double? = nil
    @Published private(set) var motionPermissionDenied: Bool = false
    private let manaRegenPerSecond: Int = 3
    let attackManaCost: Int = 5
    var isNearbyInteractionAvailable: Bool { nearbyInteraction != nil }

    init(sessionID: String,
         service: BattleService,
         haptics: HapticsService = ServiceFactory.makeHapticsService(),
         audio: AudioService = ServiceFactory.makeAudioService(),
         motionService: MotionService? = nil,
         nearbyInteraction: NearbyInteractionService? = nil) {
        self.sessionID = sessionID
        self.service = service
        self.haptics = haptics
        self.audio = audio
        self.motionService = motionService
        self.nearbyInteraction = nearbyInteraction

        if let nearbyInteraction {
            nearbyInteraction.$status
                .receive(on: RunLoop.main)
                .sink { [weak self] status in
                    self?.nearbyStatus = status
                }
                .store(in: &cancellables)

            nearbyInteraction.$reading
                .receive(on: RunLoop.main)
                .sink { [weak self] reading in
                    self?.nearbyReading = reading
                }
                .store(in: &cancellables)

            nearbyInteraction.$encodedDiscoveryToken
                .compactMap { $0 }
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak self] token in
                    guard let self else { return }
                    Task {
                        await self.service.publishNearbyInteractionToken(token)
                    }
                }
                .store(in: &cancellables)
        }
    }

    func onAppear() {
        guard !isJoining else { return }
        isJoining = true
        phase = .ready
        haptics.prepare()
        audio.prepare()
        if let nearbyInteraction {
            nearbyInteraction.clearPeerToken()
            nearbyInteraction.prepare()
            startNearbyEventsListener()
        }
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
                            let prev = self.lastState
                            self.lastState = next

                            let localMana = self.state.selfStatus.mana
                            var merged = next
                            merged.selfStatus = BattleParticipant(
                                displayName: next.selfStatus.displayName,
                                hp: next.selfStatus.hp,
                                maxHp: next.selfStatus.maxHp,
                                mana: localMana,
                                maxMana: next.selfStatus.maxMana
                            )
                            self.logger.debug("[Battle] merge mana (client-authoritative) local=\(localMana, privacy: .public) remote=\(next.selfStatus.mana, privacy: .public)")
                            self.state = merged

                            if let prev, next.selfStatus.hp < prev.selfStatus.hp {
                                self.haptics.playerHit()
                                self.audio.play(effect: .hit)
                            }
                            if let prev, prev.chantProgress < 1.0, next.chantProgress >= 1.0 {
                                self.haptics.specialReady()
                            }

                            if next.opponentStatus.hp <= 0 {
                                if self.phase != .result(.win) {
                                    self.phase = .result(.win)
                                    self.haptics.win()
                                    self.audio.play(effect: .win)
                                }
                            } else if next.selfStatus.hp <= 0 {
                                if self.phase != .result(.lose) {
                                    self.phase = .result(.lose)
                                    self.haptics.lose()
                                    self.audio.play(effect: .lose)
                                }
                            }
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
        haptics.attackTap()
        decreaseMana(by: attackManaCost)
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
        audio.stopAll()
        motionStreamTask?.cancel(); motionStreamTask = nil
        manaRegenTask?.cancel(); manaRegenTask = nil
        stepRatePerSec = nil
        motionPermissionDenied = false
        if let nearbyInteraction {
            nearbyInteraction.suspend()
        }
        nearbyEventsTask?.cancel(); nearbyEventsTask = nil
        nearbyErrorMessage = nil
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

    private func startNearbyEventsListener() {
        guard nearbyEventsTask == nil else { return }
        nearbyEventsTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.service.nearbyInteractionEvents()
            for await event in stream {
                await self.handleNearbyEvent(event)
            }
            await MainActor.run {
                self.nearbyEventsTask = nil
            }
        }
    }

    private func handleNearbyEvent(_ event: NearbyInteractionEvent) {
        guard let nearbyInteraction else { return }
        switch event {
        case .peerToken(let token):
            nearbyErrorMessage = nil
            nearbyInteraction.setPeerToken(fromBase64: token)
        case .cleared:
            nearbyErrorMessage = nil
            nearbyInteraction.clearPeerToken()
            nearbyInteraction.resume()
            if let token = nearbyInteraction.encodedDiscoveryToken {
                Task {
                    await service.publishNearbyInteractionToken(token)
                }
            }
        case .error(let message):
            nearbyErrorMessage = message
            nearbyInteraction.suspend()
        }
    }
}
