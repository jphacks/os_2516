import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class UIKitHapticsService: HapticsService {
    #if canImport(UIKit)
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()
    #endif

    func prepare() {
        #if canImport(UIKit)
        impactLight.prepare(); impactMedium.prepare(); impactHeavy.prepare(); notify.prepare()
        #endif
    }

    func stop() { /* no-op */ }

    func attackTap() {
        #if canImport(UIKit)
        impactMedium.impactOccurred()
        #endif
    }

    func playerHit() {
        #if canImport(UIKit)
        impactHeavy.impactOccurred()
        #endif
    }

    func specialReady() {
        #if canImport(UIKit)
        notify.notificationOccurred(.success)
        #endif
    }

    func specialCast() {
        #if canImport(UIKit)
        impactHeavy.impactOccurred(intensity: 1.0)
        #endif
    }

    func win() {
        #if canImport(UIKit)
        notify.notificationOccurred(.success)
        #endif
    }

    func lose() {
        #if canImport(UIKit)
        notify.notificationOccurred(.error)
        #endif
    }
}

