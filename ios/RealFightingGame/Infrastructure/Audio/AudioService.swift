import Foundation

enum AudioEffect: CaseIterable {
    case hit
    case win
    case lose

    var fileName: String {
        switch self {
        case .hit:
            return "hit.mp3"
        case .win:
            return "win.mp3"
        case .lose:
            return "lose.mp3"
        }
    }
}

protocol AudioService {
    func prepare()
    func play(effect: AudioEffect)
    func playMagic(fileName: String)
    func stopAll()
}
