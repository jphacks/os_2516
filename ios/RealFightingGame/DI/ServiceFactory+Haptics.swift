import Foundation
#if canImport(CoreHaptics)
import CoreHaptics
#endif

extension ServiceFactory {
    static func makeHapticsService() -> HapticsService {
        let disabled = ProcessInfo.processInfo.environment["USE_HAPTICS"] == "0"
        if disabled { return NoopHapticsService() }

        #if targetEnvironment(simulator)
        // SimulatorはUIKitの簡易版へ
        return UIKitHapticsService()
        #else
        #if canImport(CoreHaptics)
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            return CoreHapticsService()
        }
        #endif
        return UIKitHapticsService()
        #endif
    }
}

