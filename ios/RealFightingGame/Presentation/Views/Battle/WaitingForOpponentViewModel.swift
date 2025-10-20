import Foundation
import Combine

@MainActor
final class WaitingForOpponentViewModel: ObservableObject {
    @Published private(set) var opponentName: String? = nil
    @Published private(set) var isReady: Bool = false

    let sessionID: String
    private let service: BattleService
    private var statesTask: Task<Void, Never>?

    init(sessionID: String, service: BattleService) {
        self.sessionID = sessionID
        self.service = service
    }

    func onAppear() {
        // subscribe to remote states and observe when an opponent appears
        statesTask = Task { [weak self] in
            guard let self else { return }
            let stream = await service.states()
            for await s in stream {
                // when opponent display name is available, mark ready
                if s.opponentStatus.displayName != "Opponent" {
                    self.opponentName = s.opponentStatus.displayName
                }
                if s.opponentStatus.displayName != "Opponent" || s.opponentStatus.hp != 100 || s.opponentStatus.mana != 100 {
                    // heuristics: some non-default data implies an opponent is present
                    self.isReady = true
                    break
                }
            }
        }
    }

    func cancel() async {
        statesTask?.cancel()
        await service.end()
    }
}
