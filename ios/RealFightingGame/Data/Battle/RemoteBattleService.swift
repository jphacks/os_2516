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
        let response = try await createSession(stageId: stageId)
        activeSessionId = response.sessionId
        selfPlayerId = response.playerId
        opponentPlayerId = response.opponentId

        let state = makeBattleState(from: response.state)
        currentState = state
        publish(state)

        try await ensureSocket()

        return state
    }

    func send(_ action: BattleAction) async {
        guard let socket = webSocketTask,
              let sessionId = activeSessionId,
              let playerId = selfPlayerId,
              let opponentId = opponentPlayerId,
              let state = currentState else { return }

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
        socket.send(.data(data)) { [weak self] error in
            if let error {
                print("[RemoteBattleService] send error: \(error)")
                Task { await self?.closeSocket() }
            }
        }
    }

    func states() async -> AsyncStream<BattleState> {
        if let stream = streamCache {
            return stream
        }

        let stream = AsyncStream<BattleState> { continuation in
            Task { [weak self] in
                await self?.setContinuation(continuation)
            }
        }
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
        if let socket = webSocketTask {
            let message = ["kind": "end"]
            if let data = try? JSONSerialization.data(withJSONObject: message, options: []) {
                socket.send(.data(data)) { _ in }
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
        var request = URLRequest(url: baseURL.appendingPathComponent("api/game_sessions"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["stage_id": stageId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw NSError(domain: "RemoteBattleService", code: httpStatusCode(response), userInfo: [NSLocalizedDescriptionKey: "session creation failed"])
        }

        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(CreateSessionResponse.self, from: data)

        if opponentPlayerId == nil {
            opponentPlayerId = payload.opponentId
        }

        return payload
    }

    private func ensureSocket() async throws {
        guard webSocketTask == nil,
              let sessionId = activeSessionId,
              let playerId = selfPlayerId else { return }

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
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        guard let socket = webSocketTask else { return }
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
                break
            }
        }
        await closeSocket()
    }

    private func handle(messageData: Data) async {
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(WSServerMessage.self, from: messageData) else {
            return
        }

        if let state = payload.state {
            if opponentPlayerId == nil {
                if let other = state.players.first(where: { $0.playerId != selfPlayerId }) {
                    opponentPlayerId = other.playerId
                }
            }

            let battleState = makeBattleState(from: state)
            currentState = battleState
            publish(battleState)
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
    }

    private func publish(_ state: BattleState) {
        streamContinuation?.yield(state)
    }

    private func closeSocket() async {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func httpStatusCode(_ response: URLResponse) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? -1
    }
}

private extension URL {
    func replacingScheme(_ scheme: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        return components?.url ?? self
    }
}
