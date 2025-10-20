import CoreLocation
import Foundation

actor RemoteBattleService: BattleService {
    private struct CreateSessionResponse: Decodable {
        let sessionId: String
        let playerId: String
        let opponentId: String?
        let stageId: String
        let state: WSStatePayload
    }

    private struct WSStatePayload: Decodable {
        struct Player: Decodable {
            let playerId: String
            let role: String
            let displayName: String?
            let hp: Int
            let mp: Int
            let stance: String?
            let lastPositionId: String?
            let position: WSPositionPayload?
        }

        let sessionId: String
        let stageId: String
        let status: String
        let mode: String
        let players: [Player]
    }

    private struct WSEventPayload: Decodable {
        let triggerId: String
        let targetId: String
        let triggerHp: Int
        let targetHp: Int
        let triggerMp: Int?
        let targetMp: Int?
        let category: String
        let type: String
    }

    private struct WSPositionPayload: Decodable {
        struct Location: Decodable {
            let lat: Double
            let lon: Double
            let alt: Double?
        }

        struct Accuracy: Decodable {
            let horizontal: Double
            let vertical: Double?
            let heading: Double?
        }

        let playerId: String
        let timestamp: Date
        let location: Location
        let heading: Double
        let accuracy: Accuracy?
    }

    private struct WSAttackResultPayload: Decodable {
        let attackId: String
        let attackerId: String
        let targetId: String
        let chargeLevel: Int
        let hit: Bool
        let damage: Int
        let triggerHp: Int
        let targetHp: Int
        let triggerMp: Int?
        let targetMp: Int?
        let occurredAt: Date
    }

    private struct WSServerMessage: Decodable {
        let kind: String
        let event: WSEventPayload?
        let state: WSStatePayload?
        let position: WSPositionPayload?
        let attackResult: WSAttackResultPayload?
        let error: WSErrorPayload?
        let info: String?
    }

    private struct WSErrorPayload: Decodable {
        let code: String
        let message: String
    }

    private struct PositionUpdateMessage: Encodable {
        let kind = "position_update"
        let sessionId: String
        let payload: Payload

        struct Payload: Encodable {
            struct Location: Encodable {
                let lat: Double
                let lon: Double
                let alt: Double?
            }

            struct Accuracy: Encodable {
                let horizontal: Double
                let vertical: Double?
                let heading: Double?
            }

            let timestamp: Date
            let location: Location
            let heading: Double
            let accuracy: Accuracy?
        }
    }

    private struct AttackTriggerMessage: Encodable {
        let kind = "attack_triggered"
        let sessionId: String
        let targetId: String
        let payload: Payload

        struct Payload: Encodable {
            let timestamp: Date
            let location: PositionUpdateMessage.Payload.Location
            let heading: Double
            let accuracy: PositionUpdateMessage.Payload.Accuracy?
            let attackId: String
            let chargeLevel: Int?
        }
    }

    private let baseURL: URL
    private let token: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var activeSessionId: String?
    private var selfPlayerId: String?
    private var opponentPlayerId: String?
    private var currentState: BattleState?

    private var streamContinuation: AsyncStream<BattleState>.Continuation?
    private var streamCache: AsyncStream<BattleState>?

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectionTask: Task<Void, Never>?
    private var reconnectDelayNanoseconds: UInt64 = RemoteBattleService.initialReconnectDelay
    private var connectionMonitorTask: Task<Void, Never>?

    private var latestPositions: [String: WSPositionPayload] = [:]
    private var lastKnownSelfPosition: BattlePositionUpdate?

    private let attackDamage = 12
    private let specialDamage = 26
    // position updates older than this (seconds) will be ignored for UI updates
    private let positionFreshnessThreshold: TimeInterval = 2.0

    init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func join(sessionID stageId: String) async throws -> BattleState {
        log("join requested for stageId=\(stageId)")
        cancelScheduledReconnect()
        reconnectDelayNanoseconds = RemoteBattleService.initialReconnectDelay
        let response = try await createSession(stageId: stageId)
        activeSessionId = response.sessionId
        selfPlayerId = response.playerId
        opponentPlayerId = response.opponentId

        let state = makeBattleState(from: response.state)
        currentState = state
        publish(state)

        try await ensureSocket()
        startConnectionMonitor()

        log("join completed sessionId=\(response.sessionId) selfPlayerId=\(response.playerId) opponentPlayerId=\(response.opponentId ?? "nil")")

        return state
    }

    /// Public accessor to observe whether an opponent player id has already been observed by the service.
    /// Used by UI code to decide whether to wait for another participant.
    func knownOpponentId() async -> String? {
        return opponentPlayerId
    }

    func currentSessionId() async -> String? {
        return activeSessionId
    }

    func send(_ action: BattleAction) async {
        guard let sessionId = activeSessionId,
              let playerId = selfPlayerId,
              let opponentId = opponentPlayerId else {
            log("send aborted due to missing identifiers")
            return
        }

        let payload: (selfHp: Int, opponentHp: Int, category: String, type: String)?
        switch action {
        case .attack:
            payload = (currentState?.selfStatus.hp ?? 0,
                       max(0, (currentState?.opponentStatus.hp ?? 0) - attackDamage),
                       "attack",
                       "basic")
        case .guard:
            payload = (currentState?.selfStatus.hp ?? 0,
                       currentState?.opponentStatus.hp ?? 0,
                       "system",
                       "guard")
        case .special:
            payload = (currentState?.selfStatus.hp ?? 0,
                       max(0, (currentState?.opponentStatus.hp ?? 0) - specialDamage),
                       "attack",
                       "special")
        }

        guard let info = payload else { return }
        let message: [String: Any] = [
            "kind": "event",
            "session_id": sessionId,
            "trigger_id": playerId,
            "target_id": opponentId,
            "trigger_hp": info.selfHp,
            "target_hp": info.opponentHp,
            "category": info.category,
            "type": info.type
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message, options: []) else { return }
        do {
            try await ensureSocket()
            guard let socket = webSocketTask else { return }
            socket.send(.data(data)) { [weak self] error in
                if let error {
                    self?.log("send error: \(error)")
                }
            }
        } catch {
            log("send ensureSocket failed: \(error)")
        }
    }

    func states() async -> AsyncStream<BattleState> {
        if let stream = streamCache {
            log("states returning cached stream")
            return stream
        }

        let stream = AsyncStream<BattleState> { continuation in
            Task { [weak self] in
                await self?.setContinuation(continuation)
            }
        }
        log("states creating new stream")
        streamCache = stream
        return stream
    }

    func perform(action: BattleAction) async throws -> BattleState {
        await send(action)
        guard let state = currentState else {
            throw NSError(domain: "RemoteBattleService", code: -1, userInfo: [NSLocalizedDescriptionKey: "state unavailable"])
        }
        return state
    }

    func end() async {
        log("end requested")
        if let socket = webSocketTask {
            let message = ["kind": "end"]
            if let data = try? JSONSerialization.data(withJSONObject: message, options: []) {
                socket.send(.data(data)) { _ in }
                log("sent end message")
            }
        }
        await closeSocket(shouldReconnect: false)
        streamContinuation?.finish()
        streamContinuation = nil
        streamCache = nil
        currentState = nil
        activeSessionId = nil
        selfPlayerId = nil
        opponentPlayerId = nil
        latestPositions.removeAll()
        lastKnownSelfPosition = nil
        cancelScheduledReconnect()
        stopConnectionMonitor()
    }

    func sendPositionUpdate(_ update: BattlePositionUpdate) async {
        guard let sessionId = activeSessionId,
              let playerId = selfPlayerId else {
            log("position update skipped: identifiers unavailable")
            return
        }
        lastKnownSelfPosition = update
        let payload = PositionUpdateMessage.Payload(
            timestamp: update.timestamp,
            location: .init(lat: update.coordinate.latitude, lon: update.coordinate.longitude, alt: update.altitude),
            heading: update.heading,
            accuracy: PositionUpdateMessage.Payload.Accuracy(
                horizontal: update.horizontalAccuracy,
                vertical: update.verticalAccuracy,
                heading: update.headingAccuracy
            )
        )
        let message = PositionUpdateMessage(sessionId: sessionId, payload: payload)
        do {
            try await ensureSocket()
            guard let socket = webSocketTask else { return }
            let data = try encoder.encode(message)
            socket.send(.data(data)) { [weak self] error in
                if let error { self?.log("position send error: \(error)") }
            }
        } catch {
            log("position ensureSocket failed: \(error)")
        }
    }

    func triggerAttack(with context: BattleAttackContext) async {
        guard let sessionId = activeSessionId,
              let playerId = selfPlayerId else {
            log("attack trigger skipped: identifiers unavailable")
            return
        }
        let opponentId: String
        if let existing = opponentPlayerId {
            opponentId = existing
        } else if let stateOpp = currentState?.opponentStatus.displayName { // fallback logging
            log("opponent id unresolved while triggering attack (\(stateOpp))")
            return
        } else {
            log("opponent id unresolved while triggering attack")
            return
        }

        lastKnownSelfPosition = context.position
        let location = PositionUpdateMessage.Payload.Location(
            lat: context.position.coordinate.latitude,
            lon: context.position.coordinate.longitude,
            alt: context.position.altitude
        )
        let accuracy = PositionUpdateMessage.Payload.Accuracy(
            horizontal: context.position.horizontalAccuracy,
            vertical: context.position.verticalAccuracy,
            heading: context.position.headingAccuracy
        )
        let message = AttackTriggerMessage(
            sessionId: sessionId,
            targetId: opponentId,
            payload: .init(
                timestamp: context.position.timestamp,
                location: location,
                heading: context.position.heading,
                accuracy: accuracy,
                attackId: context.attackId?.uuidString ?? UUID().uuidString,
                chargeLevel: context.chargeLevel
            )
        )
        do {
            try await ensureSocket()
            guard let socket = webSocketTask else { return }
            let data = try encoder.encode(message)
            socket.send(.data(data)) { [weak self] error in
                if let error { self?.log("attack trigger send error: \(error)") }
            }
        } catch {
            log("attack trigger ensureSocket failed: \(error)")
        }
    }

    // MARK: - Private helpers

    private func createSession(stageId: String) async throws -> CreateSessionResponse {
        let url = baseURL.appendingPathComponent("api/game_sessions")
        log("createSession request stageId=\(stageId) url=\(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["stage_id": stageId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            log("createSession failed status=\((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw NSError(domain: "RemoteBattleService", code: httpStatusCode(response), userInfo: [NSLocalizedDescriptionKey: "session creation failed"])
        }
        log("createSession succeeded status=\(http.statusCode)")

        let payload = try decoder.decode(CreateSessionResponse.self, from: data)
        log("createSession response sessionId=\(payload.sessionId) playerId=\(payload.playerId) opponentId=\(payload.opponentId ?? "nil")")

        if opponentPlayerId == nil {
            opponentPlayerId = payload.opponentId
        }

        return payload
    }

    private func ensureSocket() async throws {
        guard webSocketTask == nil else {
            log("ensureSocket skipped because a socket already exists")
            return
        }

        guard let sessionId = activeSessionId,
              let playerId = selfPlayerId else {
            log("ensureSocket aborted: missing identifiers")
            return
        }

        guard var components = URLComponents(url: baseURL.appendingPathComponent("ws"), resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "RemoteBattleService", code: -2, userInfo: [NSLocalizedDescriptionKey: "invalid websocket url"])
        }

        components.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "player_id", value: playerId)
        ]

        guard var url = components.url else {
            throw NSError(domain: "RemoteBattleService", code: -2, userInfo: [NSLocalizedDescriptionKey: "invalid websocket url"])
        }

        if url.scheme == "https" {
            url = url.replacingScheme("wss")
        } else if url.scheme == "http" {
            url = url.replacingScheme("ws")
        }

        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        task.resume()
        webSocketTask = task
        log("websocket started url=\(url.absoluteString)")
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        guard let socket = webSocketTask else { return }
        log("receiveLoop started")
        while true {
            do {
                let message = try await socket.receive()
                switch message {
                case .data(let data):
                    await handle(messageData: data)
                case .string(let string):
                    if let data = string.data(using: .utf8) {
                        await handle(messageData: data)
                    }
                @unknown default:
                    break
                }
            } catch {
                log("receiveLoop error: \(error)")
                break
            }
        }
        log("receiveLoop ended")
        await closeSocket()
    }

    private func handle(messageData: Data) async {
        let raw = String(data: messageData, encoding: .utf8) ?? "<binary>"
        guard let payload = try? decoder.decode(WSServerMessage.self, from: messageData) else {
            log("failed to decode message raw=\(raw)")
            return
        }
        log("decoded message kind=\(payload.kind)")

        if let statePayload = payload.state {
            // debug: list display names included in state
            var names: [String] = []
            for p in statePayload.players { names.append(p.displayName ?? p.role) }
            log("ws received state players=\(names)")
            apply(statePayload)
        }

        if let event = payload.event {
            apply(event: event)
        }

        if let position = payload.position {
            apply(position: position)
        }

        if let result = payload.attackResult {
            log("attack_result received hit=\(result.hit) damage=\(result.damage)")
        }

        if let error = payload.error {
            log("server error code=\(error.code) message=\(error.message)")
        }
    }

    private func apply(_ statePayload: WSStatePayload) {
        if opponentPlayerId == nil {
            if let other = statePayload.players.first(where: { $0.playerId != selfPlayerId }) {
                opponentPlayerId = other.playerId
                log("opponentPlayerId resolved=\(other.playerId)")
            }
        }

        let newState = makeBattleState(from: statePayload)
        currentState = newState
        publish(newState)
        log("state updated selfHp=\(newState.selfStatus.hp) opponentHp=\(newState.opponentStatus.hp)")
    }

    private func apply(position: WSPositionPayload) {
        // Ignore stale updates
        let now = Date()
        let age = now.timeIntervalSince(position.timestamp)
        if age > positionFreshnessThreshold {
            log("ignoring stale position for \(position.playerId) age=\(age)")
            return
        }

        latestPositions[position.playerId] = position
        updateTelemetryFromPositions()
    }

    private func updateTelemetryFromPositions() {
        guard var state = currentState else { return }
        guard let selfId = selfPlayerId else { return }
        guard let selfPos = latestPositions[selfId] else { return }

        let opponentId: String
        if let cached = opponentPlayerId {
            opponentId = cached
        } else if let inferred = latestPositions.keys.first(where: { $0 != selfId }) {
            opponentPlayerId = inferred
            opponentId = inferred
        } else {
            return
        }

        guard let opponentPos = latestPositions[opponentId] else { return }

        let selfLocation = CLLocation(latitude: selfPos.location.lat, longitude: selfPos.location.lon)
        let opponentLocation = CLLocation(latitude: opponentPos.location.lat, longitude: opponentPos.location.lon)
        let distance = selfLocation.distance(from: opponentLocation)
        let heading = opponentPos.heading
        let timestamp = opponentPos.timestamp

        let telemetry = BattleTelemetry(distanceMeters: distance, headingDegrees: heading, lastUpdate: timestamp)
        state.telemetry = telemetry
        currentState = state
        publish(state)
    }

    private func makeBattleState(from state: WSStatePayload) -> BattleState {
        let selfPlayer = state.players.first { $0.playerId == selfPlayerId }
        if opponentPlayerId == nil {
            if let other = state.players.first(where: { $0.playerId != selfPlayerId }) {
                opponentPlayerId = other.playerId
            }
        }
        let opponent = state.players.first { $0.playerId == opponentPlayerId }

        // ingest initial positions from state payload if present
        for p in state.players {
            if let pos = p.position {
                latestPositions[p.playerId] = pos
            }
        }
        // attempt to update telemetry immediately if possible
        updateTelemetryFromPositions()

        let selfStatus = BattleParticipant(
            displayName: selfPlayer?.displayName ?? selfPlayer?.role.capitalized ?? "You",
            hp: selfPlayer?.hp ?? currentState?.selfStatus.hp ?? 100,
            maxHp: currentState?.selfStatus.maxHp ?? 100,
            mana: selfPlayer?.mp ?? currentState?.selfStatus.mana ?? 100,
            maxMana: currentState?.selfStatus.maxMana ?? 100
        )

        let opponentStatus = BattleParticipant(
            displayName: opponent?.displayName ?? opponent?.role.capitalized ?? "Opponent",
            hp: opponent?.hp ?? currentState?.opponentStatus.hp ?? 100,
            maxHp: currentState?.opponentStatus.maxHp ?? 100,
            mana: opponent?.mp ?? currentState?.opponentStatus.mana ?? 100,
            maxMana: currentState?.opponentStatus.maxMana ?? 100
        )

        let telemetry = currentState?.telemetry ?? BattleTelemetry(distanceMeters: 10, headingDegrees: 0, lastUpdate: Date())

        return BattleState(
            selfStatus: selfStatus,
            opponentStatus: opponentStatus,
            telemetry: telemetry,
            chantProgress: currentState?.chantProgress ?? 0,
            runEnergy: currentState?.runEnergy ?? 0
        )
    }

    private func setContinuation(_ continuation: AsyncStream<BattleState>.Continuation) {
        streamContinuation = continuation
        if let state = currentState {
            continuation.yield(state)
        }
        log("continuation set currentStateExists=\(currentState != nil)")
    }

    private func publish(_ state: BattleState) {
        streamContinuation?.yield(state)
    }

    private func apply(event: WSEventPayload) {
        guard var state = currentState else {
            log("event ignored due to missing state")
            return
        }

        var selfStatus = state.selfStatus
        var opponentStatus = state.opponentStatus

        let isTriggerSelf = event.triggerId == selfPlayerId
        let isTargetSelf = event.targetId == selfPlayerId
        let isTriggerOpponent = event.triggerId == opponentPlayerId
        let isTargetOpponent = event.targetId == opponentPlayerId

        if isTriggerSelf {
            selfStatus = selfStatus.with(hp: event.triggerHp, mana: event.triggerMp)
        } else if isTriggerOpponent {
            opponentStatus = opponentStatus.with(hp: event.triggerHp, mana: event.triggerMp)
        }

        if isTargetSelf {
            selfStatus = selfStatus.with(hp: event.targetHp, mana: event.targetMp)
        } else if isTargetOpponent {
            opponentStatus = opponentStatus.with(hp: event.targetHp, mana: event.targetMp)
        }

        let selfChanged = selfStatus.hp != state.selfStatus.hp || selfStatus.mana != state.selfStatus.mana
        let opponentChanged = opponentStatus.hp != state.opponentStatus.hp || opponentStatus.mana != state.opponentStatus.mana

        guard selfChanged || opponentChanged else { return }

        state.selfStatus = selfStatus
        state.opponentStatus = opponentStatus
        currentState = state
        publish(state)
    }

    private func closeSocket(shouldReconnect: Bool = true) async {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        log("websocket closed")
        if shouldReconnect {
            scheduleReconnect()
        } else {
            cancelScheduledReconnect()
            stopConnectionMonitor()
        }
    }

    private func scheduleReconnect() {
        guard activeSessionId != nil else {
            log("scheduleReconnect skipped: no active session")
            return
        }
        guard reconnectionTask == nil else {
            log("scheduleReconnect skipped: task already scheduled")
            return
        }

        let delay = reconnectDelayNanoseconds
        reconnectionTask = Task { [weak self] in
            guard let self else { return }
            await self.performReconnectAttempt(after: delay)
        }
    }

    private func performReconnectAttempt(after delay: UInt64) async {
        log("reconnect scheduled delay=\(Double(delay)/1_000_000_000.0)s")
        try? await Task.sleep(nanoseconds: delay)
        do {
            try await ensureSocket()
            reconnectDelayNanoseconds = RemoteBattleService.initialReconnectDelay
            reconnectionTask = nil
        } catch {
            log("reconnect attempt failed: \(error)")
            reconnectDelayNanoseconds = min(delay * 2, 30_000_000_000)
            reconnectionTask = nil
            scheduleReconnect()
        }
    }

    private func cancelScheduledReconnect() {
        reconnectionTask?.cancel()
        reconnectionTask = nil
    }

    private func startConnectionMonitor() {
        guard connectionMonitorTask == nil else { return }
        connectionMonitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if await self.webSocketTask == nil {
                    do {
                        try await self.ensureSocket()
                    } catch {
                        self.log("connection monitor ensureSocket failed: \(error)")
                    }
                }
            }
        }
    }

    private func stopConnectionMonitor() {
        connectionMonitorTask?.cancel()
        connectionMonitorTask = nil
    }

    private func httpStatusCode(_ response: URLResponse) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? -1
    }

    nonisolated private func log(_ message: String) {
        print("[RemoteBattleService] \(message)")
    }
}

private extension BattleParticipant {
    func with(hp: Int, mana: Int?) -> BattleParticipant {
        BattleParticipant(displayName: displayName,
                          hp: hp,
                          maxHp: maxHp,
                          mana: mana ?? self.mana,
                          maxMana: maxMana)
    }
}

private extension URL {
    func replacingScheme(_ newScheme: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.scheme = newScheme
        return components?.url ?? self
    }
}

private extension RemoteBattleService {
    static let initialReconnectDelay: UInt64 = 1_000_000_000
}
