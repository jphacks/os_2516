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
    private var lastSteps: Int?
    private var lastTimestamp: Date?
    private var lastEmitAt: Date?
    private var watchdogTask: Task<Void, Never>?
    private var runningState: Bool = false
    private var smoothedCadence: Double?
    private let runStartThreshold: Double = 1.30 // ヒステリシス: 開始
    private let runStopThreshold: Double = 1.05  // ヒステリシス: 停止
    private let runStartHoldTime: TimeInterval = 0.4
    private let minStopHoldTime: TimeInterval = 0.6
    private let watchdogTimeout: TimeInterval = 2.2
    private let emaAlpha: Double = 0.55
    private var belowStopSince: Date?
    private var aboveStartSince: Date?

    func updates() -> AsyncStream<MotionUpdate> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            self.continuation?.finish()
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.pedometer.stopUpdates()
                self?.watchdogTask?.cancel(); self?.watchdogTask = nil
                self?.continuation = nil
                self?.lastSteps = nil
                self?.lastTimestamp = nil
                self?.lastEmitAt = nil
                self?.smoothedCadence = nil
            }

            // 権限・機能の状態をログ出力
            let authStatus = CMPedometer.authorizationStatus()
            let authDesc: String = {
                switch authStatus {
                case .notDetermined: return "notDetermined"
                case .restricted:    return "restricted"
                case .denied:        return "denied"
                case .authorized:    return "authorized"
                @unknown default:    return "unknown"
                }
            }()
            let available = CMPedometer.isStepCountingAvailable()
            self.logger.debug("[Motion] pedometer auth=\(authDesc, privacy: .public), stepCountingAvailable=\(available, privacy: .public)")

            guard available else {
                self.logger.debug("[Motion] Step counting not available")
                continuation.finish()
                return
            }

            // 直近数秒さかのぼって購読することで、開始直後の反映を速める
            self.logger.debug("[Motion] startUpdates(from: -5s)")
            self.pedometer.startUpdates(from: Date(timeIntervalSinceNow: -5)) { [weak self] data, error in
                guard let self else { return }
                if let error {
                    self.logger.debug("[Motion] pedometer error: \(error.localizedDescription, privacy: .public)")
                    return
                }
                guard let data else { return }
                // フォールバック: 歩数差分から自前cadenceを算出
                let steps = data.numberOfSteps.intValue
                let ts = data.endDate
                var derivedRate: Double = 0
                if let ls = self.lastSteps, let lt = self.lastTimestamp {
                    let dSteps = max(0, steps - ls)
                    let dt = max(0.1, ts.timeIntervalSince(lt))
                    derivedRate = Double(dSteps) / dt
                    self.logger.debug("[Motion] Δsteps=\(dSteps, privacy: .public), Δt=\(dt, privacy: .public)s, derived=\(derivedRate, privacy: .public) sps")
                }
                self.lastSteps = steps
                self.lastTimestamp = ts

                // currentCadence があれば優先、なければ derived を使用
                let currentCadenceRaw = data.currentCadence?.doubleValue ?? -1
                let cadenceSource: String
                let cadence: Double
                if currentCadenceRaw > 0 {
                    cadence = currentCadenceRaw
                    cadenceSource = "currentCadence"
                } else {
                    cadence = derivedRate
                    cadenceSource = "derived"
                }
                let sampleForStart = max(cadence, derivedRate)
                let sampleForStop = min(cadence, derivedRate > 0 ? derivedRate : cadence)
                if let previous = self.smoothedCadence {
                    self.smoothedCadence = previous + self.emaAlpha * (sampleForStart - previous)
                } else {
                    self.smoothedCadence = sampleForStart
                }
                let smoothed = self.smoothedCadence ?? sampleForStart
                let startThreshold = self.runStartThreshold
                let stopReference = min(sampleForStop, smoothed)
                let startReference = max(sampleForStart, smoothed)
                let now = Date()
                let stopHoldElapsed: Double
                let startHoldElapsed: Double
                if let since = self.belowStopSince {
                    stopHoldElapsed = now.timeIntervalSince(since)
                } else {
                    stopHoldElapsed = -1
                }
                if let since = self.aboveStartSince {
                    startHoldElapsed = now.timeIntervalSince(since)
                } else {
                    startHoldElapsed = -1
                }
                self.logger.debug("[Motion] currentCadence=\(currentCadenceRaw) sps, derived=\(derivedRate) sps, used=\(cadenceSource, privacy: .public), startRef=\(startReference, privacy: .public), stopRef=\(stopReference, privacy: .public), smoothed=\(smoothed, privacy: .public), startThreshold=\(startThreshold, privacy: .public), startHoldElapsed=\(startHoldElapsed, privacy: .public), stopHoldElapsed=\(stopHoldElapsed, privacy: .public)")
                // ヒステリシス適用: 走行開始/終了の閾値を分けてフリップ抑制
                if self.runningState {
                    if stopReference <= self.runStopThreshold {
                        if self.belowStopSince == nil {
                            self.belowStopSince = now
                        }
                        if let since = self.belowStopSince, now.timeIntervalSince(since) >= self.minStopHoldTime {
                            self.runningState = false
                            self.belowStopSince = nil
                            self.aboveStartSince = nil
                        }
                    } else {
                        self.belowStopSince = nil
                        self.aboveStartSince = nil
                    }
                } else {
                    if startReference >= startThreshold {
                        if self.aboveStartSince == nil {
                            self.aboveStartSince = now
                        }
                        if let since = self.aboveStartSince, now.timeIntervalSince(since) >= self.runStartHoldTime {
                            self.runningState = true
                            self.belowStopSince = nil
                            self.aboveStartSince = nil
                        }
                    } else {
                        self.aboveStartSince = nil
                    }
                }
                let isRunning = self.runningState
                self.lastEmitAt = Date()
                self.logger.debug("[Motion] cadence=\(cadence, privacy: .public) sps, isRunning=\(isRunning, privacy: .public)")
                let update = MotionUpdate(isRunning: isRunning, stepRatePerSec: cadence, timestamp: ts)
                self.continuation?.yield(update)
            }
            // 無更新タイムアウト監視（一定間隔以上で停止扱い）
            self.watchdogTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    let now = Date()
                    if let last = self.lastEmitAt, now.timeIntervalSince(last) > self.watchdogTimeout {
                        self.logger.debug("[Motion] watchdog timeout -> cadence=0, isRunning=false")
                        self.lastEmitAt = now
                        self.continuation?.yield(MotionUpdate(isRunning: false, stepRatePerSec: 0, timestamp: now))
                    }
                }
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
