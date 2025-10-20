import Foundation
import Combine

@MainActor
final class WaitingForOpponentViewModel: ObservableObject {
    @Published private(set) var opponentName: String? = nil
    @Published private(set) var isReady: Bool = false

    let sessionID: String
    private let service: BattleService
    private var statesTask: Task<Void, Never>?
    private var lastPostedSessionId: String? = nil

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
                // debug log each incoming state observed by WaitingForOpponentViewModel
                print("[WaitingForOpponentVM] received state opponentName=\(s.opponentStatus.displayName) opponentHp=\(s.opponentStatus.hp) opponentMana=\(s.opponentStatus.mana)")
                // when opponent display name is available, mark ready
                if s.opponentStatus.displayName != "Opponent" {
                    self.opponentName = s.opponentStatus.displayName
                }
                if s.opponentStatus.displayName != "Opponent" || s.opponentStatus.hp != 100 || s.opponentStatus.mana != 100 {
                    // heuristics: some non-default data implies an opponent is present
                    // Check that the service actually knows the opponent id (avoid transient states during session re-creation)
                    let realSid = await service.currentSessionId()
                    let knownOpp = await service.knownOpponentId()
                    print("[WaitingForOpponentVM] heuristics matched candidate — realSid=\(String(describing: realSid)) knownOpp=\(String(describing: knownOpp)) initialSession=\(self.sessionID)")
                    // require knownOpp to be non-nil before posting; also avoid posting same session id twice
                    if let realSid = realSid, let knownOpp = knownOpp, !knownOpp.isEmpty {
                        if lastPostedSessionId == realSid {
                            print("[WaitingForOpponentVM] already posted waitingDidResolve for session=\(realSid), ignoring")
                        } else {
                            lastPostedSessionId = realSid
                            print("[WaitingForOpponentVM] posting waitingDidResolve realSid=\(realSid) initialSession=\(self.sessionID)")
                            NotificationCenter.default.post(name: .waitingDidResolve, object: realSid)
                            break
                        }
                    } else {
                        // fallback: do not post if no known opponent, but mark ready so UI can show updated info
                        print("[WaitingForOpponentVM] heuristics matched but knownOpp missing — not posting; will set isReady=true")
                        self.isReady = true
                        break
                    }
                }
            }
        }
    }

    func cancel() async {
        statesTask?.cancel()
        await service.end()
    }
}
