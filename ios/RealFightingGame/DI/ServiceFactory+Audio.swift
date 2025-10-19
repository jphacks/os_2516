import Foundation

extension ServiceFactory {
    static func makeAudioService() -> AudioService {
        let disabled = ProcessInfo.processInfo.environment["USE_AUDIO"] == "0"
        if disabled {
            return NoopAudioService()
        }
        return AVAudioService()
    }
}
