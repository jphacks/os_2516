import Foundation

struct NoopAudioService: AudioService {
    func prepare() {}
    func play(effect: AudioEffect) {}
    func playMagic(fileName: String) {}
    func stopAll() {}
}
