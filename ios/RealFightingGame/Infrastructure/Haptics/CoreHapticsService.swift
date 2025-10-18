import Foundation
#if canImport(CoreHaptics)
import CoreHaptics
#endif

final class CoreHapticsService: HapticsService {
    #if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
    private let supported: Bool = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    #else
    private let supported: Bool = false
    #endif

    init() {
        #if canImport(CoreHaptics)
        if supported {
            do {
                engine = try CHHapticEngine()
                engine?.isAutoShutdownEnabled = true
            } catch {
                engine = nil
            }
        }
        #endif
    }

    func prepare() {
        #if canImport(CoreHaptics)
        guard supported else { return }
        try? engine?.start()
        #endif
    }

    func stop() {
        #if canImport(CoreHaptics)
        try? engine?.stop(completionHandler: nil)
        #endif
    }

    func attackTap() { playTransient(intensity: 0.7, sharpness: 0.8) }
    func playerHit() { playTransient(intensity: 1.0, sharpness: 0.3) }
    func specialReady() { playTransient(intensity: 0.6, sharpness: 0.9) }
    func specialCast() { playContinuous(duration: 0.25, intensity: 0.9, sharpness: 0.6) }
    func win() { playTransient(intensity: 0.8, sharpness: 0.7) }
    func lose() { playTransient(intensity: 0.7, sharpness: 0.2) }

    private func playTransient(intensity: Float, sharpness: Float) {
        #if canImport(CoreHaptics)
        guard supported, let engine else { return }
        let ev = CHHapticEvent(eventType: .hapticTransient,
                               parameters: [
                                   CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                               ],
                               relativeTime: 0)
        do {
            let pattern = try CHHapticPattern(events: [ev], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch { /* no-op */ }
        #endif
    }

    private func playContinuous(duration: TimeInterval, intensity: Float, sharpness: Float) {
        #if canImport(CoreHaptics)
        guard supported, let engine else { return }
        let ev = CHHapticEvent(eventType: .hapticContinuous,
                               parameters: [
                                   CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                               ],
                               relativeTime: 0,
                               duration: duration)
        do {
            let pattern = try CHHapticPattern(events: [ev], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch { /* no-op */ }
        #endif
    }
}

