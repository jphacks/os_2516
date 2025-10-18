import Foundation

final class NoopHapticsService: HapticsService {
    func prepare() {}
    func stop() {}
    func attackTap() {}
    func playerHit() {}
    func specialReady() {}
    func specialCast() {}
    func win() {}
    func lose() {}
}

