import AVFoundation
import Foundation
import OSLog

final class AVAudioService: AudioService {
    private let bundle: Bundle
    private let queue = DispatchQueue(label: "com.realFightingGame.audio", qos: .userInitiated)
    private var players: [String: AVAudioPlayer] = [:]
    private let logger = Logger(subsystem: "RealFightingGame", category: "Audio")

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func prepare() {
        queue.async { [weak self] in
            guard let self else { return }
            AudioEffect.allCases.forEach { _ = self.player(for: $0.fileName) }
        }
    }

    func play(effect: AudioEffect) {
        play(fileName: effect.fileName)
    }

    func playMagic(fileName: String) {
        guard !fileName.isEmpty else { return }
        play(fileName: fileName)
    }

    func stopAll() {
        queue.async { [weak self] in
            guard let self else { return }
            let players = Array(self.players.values)
            DispatchQueue.main.async {
                for player in players {
                    player.stop()
                    player.currentTime = 0
                }
            }
        }
    }

    private func play(fileName: String) {
        queue.async { [weak self] in
            guard let self, let player = self.player(for: fileName) else { return }
            DispatchQueue.main.async {
                player.currentTime = 0
                player.play()
            }
        }
    }

    private func player(for fileName: String) -> AVAudioPlayer? {
        if let cached = players[fileName] { return cached }
        guard let url = resourceURL(for: fileName) else {
            logger.error("Audio resource not found: \(fileName, privacy: .public)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[fileName] = player
            return player
        } catch {
            logger.error("Failed to create player for \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func resourceURL(for fileName: String) -> URL? {
        let nsName = fileName as NSString
        let name = nsName.deletingPathExtension
        let ext = nsName.pathExtension.isEmpty ? nil : nsName.pathExtension
        return bundle.url(forResource: name, withExtension: ext)
    }
}
