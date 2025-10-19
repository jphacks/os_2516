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
            let hp: Int
            let mp: Int
            let stance: String?
            let lastPositionId: String?
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

    private struct WSServerMessage: Decodable {
        let kind: String
        let event: WSEventPayload?
        let state: WSStatePayload?
        let error: WSErrorPayload?
    }

    private struct WSErrorPayload: Decodable {
        let code: String
        let message: String
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

    private let attackDamage = 12
    private let specialDamage = 26

    init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func join(sessionID stageId: String) async throws -> BattleState {
        log("join requested for stageId=\(stageId)")
        let response = try await createSession(stageId: stageId)
        activeSessionId = response.sessionId
        selfPlayerId = response.playerId
        opponentPlayerId = response.opponentId

        let state = makeBattleState(from: response.state)
        currentState = state
        publish(state)

        try await ensureSocket()

        log("join completed sessionId=\(response.sessionId) selfPlayerId=\(response.playerId) opponentPlayerId=\(response.opponentId ?? "nil")")

        return state
    }

    func send(_ action: BattleAction) async {
        log("send requested action=\(action)")

        if webSocketTask == nil {
            log("send detected missing socket; attempting to re-establish")
            do {
                try await ensureSocket()
            } catch {
                log("send failed to ensure socket: \(error)")
            }
        }

        guard let socket = webSocketTask else {
            log("send aborted: webSocketTask is nil")
            return
        }
        guard let sessionId = activeSessionId else {
            log("send aborted: activeSessionId is nil")
            return
        }
        guard let playerId = selfPlayerId else {
            log("send aborted: selfPlayerId is nil")
            return
        }
        guard let opponentId = opponentPlayerId else {
            log("send aborted: opponentPlayerId is nil")
            return
        }
        guard let state = currentState else {
            log("send aborted: currentState is nil")
            return
        }

        let next: (selfHp: Int, opponentHp: Int, category: String, type: String)?
        switch action {
        case .attack:
            next = (state.selfStatus.hp, max(0, state.opponentStatus.hp - attackDamage), "attack", "basic")
        case .guard:
            next = (state.selfStatus.hp, state.opponentStatus.hp, "system", "guard")
        case .special:
            next = (state.selfStatus.hp, max(0, state.opponentStatus.hp - specialDamage), "attack", "special")
        }

        guard let payload = next else { return }

        let message: [String: Any] = [
            "kind": "event",
            "session_id": sessionId,
            "trigger_id": playerId,
            "target_id": opponentId,
            "trigger_hp": payload.selfHp,
            "target_hp": payload.opponentHp,
            "category": payload.category,
            "type": payload.type
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message, options: []) else { return }
        log("sending event sessionId=\(sessionId) triggerId=\(playerId) targetId=\(opponentId) hp=(self:\(payload.selfHp), opp:\(payload.opponentHp)) category=\(payload.category) type=\(payload.type)")
        socket.send(.data(data)) { [weak self] error in
            if let error {
                self?.log("send error: \(error)")
                Task { await self?.closeSocket() }
            } else {
                self?.log("send completed successfully for type=\(payload.type)")
            }
        }
    }

    func states() async -> AsyncStream<BattleState> {
        if let stream = streamCache {
            log("states returning cached stream")
            return stream
        }

        let stream = AsyncStream<BattleState> { continuation in
            log("AsyncStream continuation established")
            Task { [weak self] in
                await self?.setContinuation(continuation)
            }
        }
        log("states creating new stream")
        streamCache = stream
        return stream
    }

    func perform(action: BattleAction) async throws -> BattleState {
        log("perform requested action=\(action)")
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
        await closeSocket()
        streamContinuation?.finish()
        streamContinuation = nil
        streamCache = nil
        currentState = nil
        activeSessionId = nil
        selfPlayerId = nil
        opponentPlayerId = nil
    }

    // MARK: - Private

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

        decoder.keyDecodingStrategy = .convertFromSnakeCase
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
            log("ensureSocket aborted due to missing session/player identifiers")
            return
        }

        log("ensureSocket begin sessionId=\(sessionId) playerId=\(playerId)")

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
                    log("received data message bytes=\(data.count)")
                    await handle(messageData: data)
                case .string(let string):
                    log("received string message length=\(string.count)")
                    if let data = string.data(using: .utf8) {
                        await handle(messageData: data)
                    }
                @unknown default:
                    log("received unknown message")
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
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = String(data: messageData, encoding: .utf8) ?? "<binary>"
        guard let payload = try? decoder.decode(WSServerMessage.self, from: messageData) else {
            log("failed to decode message raw=\(raw)")
            return
        }
        log("decoded message kind=\(payload.kind)")

        if let state = payload.state {
            log("state payload received players=\(state.players.count) status=\(state.status)")
            if opponentPlayerId == nil {
                if let other = state.players.first(where: { $0.playerId != selfPlayerId }) {
                    opponentPlayerId = other.playerId
                    log("opponentPlayerId resolved=\(other.playerId)")
                }
            }

            let battleState = makeBattleState(from: state)
            currentState = battleState
            publish(battleState)
            log("state updated selfHp=\(battleState.selfStatus.hp) opponentHp=\(battleState.opponentStatus.hp)")
        }

        if let event = payload.event {
            log("event payload category=\(event.category) type=\(event.type) triggerId=\(event.triggerId) targetId=\(event.targetId) triggerHp=\(event.triggerHp) targetHp=\(event.targetHp)")
            apply(event: event)
        }

        if let error = payload.error {
            log("server error code=\(error.code) message=\(error.message)")
        }
    }

    private func makeBattleState(from state: WSStatePayload) -> BattleState {
        let selfPlayer = state.players.first { $0.playerId == selfPlayerId }
        if opponentPlayerId == nil {
            if let other = state.players.first(where: { $0.playerId != selfPlayerId }) {
                opponentPlayerId = other.playerId
            }
        }

        let opponent = state.players.first { $0.playerId == opponentPlayerId }

        let selfStatus = BattleParticipant(
            displayName: selfPlayer?.role.capitalized ?? "You",
            hp: selfPlayer?.hp ?? currentState?.selfStatus.hp ?? 100,
            maxHp: currentState?.selfStatus.maxHp ?? 100,
            mana: selfPlayer?.mp ?? currentState?.selfStatus.mana ?? 100,
            maxMana: currentState?.selfStatus.maxMana ?? 100
        )

        let opponentStatus = BattleParticipant(
            displayName: opponent?.role.capitalized ?? "Opponent",
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
        log("state published selfHp=\(state.selfStatus.hp) opponentHp=\(state.opponentStatus.hp)")
    }

    private func apply(event: WSEventPayload) {
        guard var state = currentState else {
            log("apply(event:) skipped because currentState is nil")
            return
        }

        var selfStatus = state.selfStatus
        var opponentStatus = state.opponentStatus

        let isTriggerSelf = event.triggerId == selfPlayerId
        let isTargetSelf = event.targetId == selfPlayerId
        let isTriggerOpponent = event.triggerId == opponentPlayerId
        let isTargetOpponent = event.targetId == opponentPlayerId

        if !(isTriggerSelf || isTriggerOpponent || isTargetSelf || isTargetOpponent) {
            log("event references unknown players trigger=\(event.triggerId) target=\(event.targetId)")
        }

        if opponentPlayerId == nil {
            if event.triggerId != selfPlayerId {
                opponentPlayerId = event.triggerId
                log("opponentPlayerId inferred from event trigger=\(event.triggerId)")
            } else if event.targetId != selfPlayerId {
                opponentPlayerId = event.targetId
                log("opponentPlayerId inferred from event target=\(event.targetId)")
            }
        }

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

        guard selfChanged || opponentChanged else {
            log("event caused no state change (ids trigger=\(event.triggerId) target=\(event.targetId))")
            return
        }

        state.selfStatus = selfStatus
        state.opponentStatus = opponentStatus
        currentState = state
        publish(state)
        log("event applied selfHp=\(selfStatus.hp) opponentHp=\(opponentStatus.hp)")
    }

    private func closeSocket() async {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        log("websocket closed")
    }

    private func httpStatusCode(_ response: URLResponse) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? -1
    }

    nonisolated private func log(_ message: String) {
        print("[RemoteBattleService] \(message)")
    }
}

private extension URL {
    func replacingScheme(_ scheme: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        return components?.url ?? self
    }
}

private extension BattleParticipant {
    func with(hp: Int, mana: Int?) -> BattleParticipant {
        BattleParticipant(
            displayName: displayName,
            hp: hp,
            maxHp: maxHp,
            mana: mana ?? self.mana,
            maxMana: maxMana
        )
    }
}
