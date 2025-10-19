import Foundation
import CoreMotion
import OSLog

struct MotionUpdate {
    let isRunning: Bool
    let stepRatePerSec: Double
    let timestamp: Date
}

protocol MotionService {
    func updates() -> AsyncStream<MotionUpdate>
    func stop()
}

final class CoreMotionMotionService: MotionService {
    private let pedometer = CMPedometer()
    private var continuation: AsyncStream<MotionUpdate>.Continuation?
    private let logger = Logger(subsystem: "RealFightingGame", category: "MotionService")

    func updates() -> AsyncStream<MotionUpdate> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            self.continuation?.finish()
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.pedometer.stopUpdates()
                self?.continuation = nil
            }

            guard CMPedometer.isStepCountingAvailable() else {
                self.logger.debug("Step counting not available")
                continuation.finish()
                return
            }

            self.pedometer.startUpdates(from: Date()) { [weak self] data, error in
                guard let self else { return }
                if let error {
                    self.logger.debug("pedometer error: \(error.localizedDescription)")
                    return
                }
                guard let data else { return }
                let cadence = data.currentCadence?.doubleValue ?? 0
                // 走行判定の閾値（暫定）
                let isRunning = cadence >= 1.4
                self.logger.debug("[Motion] cadence=\(cadence, privacy: .public) sps, isRunning=\(isRunning, privacy: .public)")
                let update = MotionUpdate(isRunning: isRunning, stepRatePerSec: cadence, timestamp: Date())
                self.continuation?.yield(update)
            }
        }
    }

    func stop() {
        pedometer.stopUpdates()
        continuation?.finish()
        continuation = nil
    }
}

struct MockMotionService: MotionService {
    let runningPattern: [Bool]
    let intervalNanoseconds: UInt64
    let runningStepRate: Double
    let walkingStepRate: Double
    let repeats: Bool

    init(
        runningPattern: [Bool] = [true, true, true, false, false],
        intervalNanoseconds: UInt64 = 1_000_000_000,
        runningStepRate: Double = 2.8,
        walkingStepRate: Double = 1.4,
        repeats: Bool = true
    ) {
        self.runningPattern = runningPattern
        self.intervalNanoseconds = intervalNanoseconds
        self.runningStepRate = runningStepRate
        self.walkingStepRate = walkingStepRate
        self.repeats = repeats
    }

    func updates() -> AsyncStream<MotionUpdate> {
        AsyncStream { continuation in
            Task {
                func yieldPattern() async {
                    for flag in runningPattern {
                        let rate = flag ? runningStepRate : walkingStepRate
                        continuation.yield(MotionUpdate(isRunning: flag, stepRatePerSec: rate, timestamp: Date()))
                        if intervalNanoseconds > 0 {
                            try? await Task.sleep(nanoseconds: intervalNanoseconds)
                        }
                    }
                }
                if repeats {
                    while !Task.isCancelled {
                        await yieldPattern()
                    }
                } else {
                    await yieldPattern()
                    continuation.finish()
                }
            }
        }
    }

    func stop() {}
}
