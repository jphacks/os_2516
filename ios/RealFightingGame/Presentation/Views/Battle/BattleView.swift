import Combine
import SwiftUI

struct BattleView: View {
    @StateObject private var viewModel: BattleViewModel
    @State private var presentedResult: BattleResult?
    @State private var lastMana: Int = 0
    @State private var manaGain: Int? = nil
    @State private var fireballTrigger: Int = 0
    @State private var showFireball: Bool = false
    #if canImport(UIKit)
    @Environment(\.openURL) private var openURL
    #endif

    init(sessionID: String = "mock",
         service: BattleService = ServiceFactory.makeBattleService(),
         motionService: MotionService? = nil,
         locationService: LocationService? = nil) {
        _viewModel = StateObject(wrappedValue: BattleViewModel(sessionID: sessionID,
                                                               service: service,
                                                               motionService: motionService,
                                                               locationService: locationService))
    }

    var body: some View {
        ZStack {
            // Fantasy background: subtle vignette + gradient + faux particles
            LinearGradient(colors: [Color(.sRGB, red: 0.02, green: 0.03, blue: 0.08), Color(.sRGB, red: 0.07, green: 0.02, blue: 0.04)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // soft vignette
            RadialGradient(gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.35)]), center: .center, startRadius: 200, endRadius: 700)
                .blendMode(.overlay)
                .ignoresSafeArea()

            // subtle floating particles
            ForEach(0..<8, id: \ .self) { i in
                Circle()
                    .fill(Color.white.opacity(0.02 + Double(i) * 0.01))
                    .frame(width: CGFloat(6 + (i % 3) * 6), height: CGFloat(6 + (i % 3) * 6))
                    .position(x: CGFloat(40 + i * 60), y: CGFloat(80 + (i % 5) * 90))
                    .blur(radius: 6)
            }

            VStack(spacing: 16) {
            // 上部: 相手のステータスのみ表示
            HStack(alignment: .top) {
                Spacer(minLength: 8)
                PlayerStatusView(
                    participant: viewModel.state.opponentStatus,
                    accent: .red,
                    alignment: .trailing
                )
            }
            .padding(.horizontal)

            // ゲージ群は削除（Guard/Special/MP 非表示）

            if viewModel.motionPermissionDenied {
                permissionBanner
            }

            Spacer(minLength: 24)

            Group {
                switch viewModelPhaseText() {
                case .some(let text):
                    Text(text)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                case .none:
                    EmptyView()
                }
            }

            Spacer()

            // 下部: 自分のステータス（MP回復時に+Xトーストとグロー）
            HStack(alignment: .bottom) {
                ZStack(alignment: .topLeading) {
                    PlayerStatusView(
                        participant: viewModel.state.selfStatus,
                        accent: .green,
                        alignment: .leading
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(.purple.opacity(manaGain != nil ? 0.35 : 0.0), lineWidth: 3)
                            .animation(.easeOut(duration: 0.3), value: manaGain != nil)
                    )
                    if let gain = manaGain {
                        Text("+\(gain)")
                            .font(.caption).bold()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(.purple)
                            .background(.ultraThinMaterial, in: Capsule())
                            .offset(y: -10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal)

            actions
            .padding(.horizontal)
            .padding(.bottom)
            .background(.clear)
        }
        }
        .overlay(alignment: .trailing) {
            RunStatusIndicator(isRunning: viewModel.isRunning,
                               rate: viewModel.stepRatePerSec)
                .padding(.trailing, 12)
        }
        .overlay(alignment: .center) {
            if showFireball {
                FireballOverlay(trigger: fireballTrigger) {
                    showFireball = false
                }
            }
            if let telemetry = viewModel.opponentIndicator {
                CenterDirectionIndicator(heading: telemetry.headingDegrees, freshnessAge: Date().timeIntervalSince(telemetry.lastUpdate))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let telemetry = viewModel.opponentIndicator {
                OpponentLocatorView(telemetry: telemetry)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .allowsHitTesting(true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: viewModelPhase) { phase in
            if case .result(let r) = phase { presentedResult = r }
        }
        .onReceive(viewModel.$phase.dropFirst()) { phase in
            if case .result(let result) = phase { presentedResult = result }
        }
        .onAppear {
            viewModel.onAppear()
            lastMana = viewModel.state.selfStatus.mana
        }
        .onDisappear { viewModel.onDisappear() }
        // MP増加のトースト表示制御
        .onChange(of: viewModel.state.selfStatus.mana) { new in
            let delta = new - lastMana
            if delta > 0 {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    manaGain = delta
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeOut(duration: 0.2)) { manaGain = nil }
                }
            }
            lastMana = new
        }
        .sheet(item: $presentedResult) { result in
            BattleResultView(result: result, onRetry: {
                presentedResult = nil
                viewModel.retry()
            }) {
                presentedResult = nil
            }
        }
        .navigationTitle("Battle")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isInputEnabled: Bool {
        if case .inputting = viewModelPhase { return true }
        return false
    }

    private var viewModelPhase: BattleViewModel.Phase { viewModel.phase }

    @Environment(\.horizontalSizeClass) private var hSize

    private var actions: some View {
        Group {
            if hSize == .regular {
                HStack { attackButton }
            } else {
                VStack { attackButton }
            }
        }
    }

    private var attackButton: some View {
        Button {
            viewModel.attackTapped()
            // ファイヤーボール発射アニメ
            fireballTrigger += 1
            showFireball = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .orange.opacity(0.6), radius: 6)
                Text("ファイヤーボール (−\(viewModel.attackManaCost))")
                    .font(.title3).bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [Color(.sRGB, red: 0.9, green: 0.36, blue: 0.12), Color(.sRGB, red: 0.7, green: 0.12, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.red.opacity(0.28), radius: 14, x: 0, y: 6)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .scaleEffect(isInputEnabled && viewModel.state.selfStatus.mana >= viewModel.attackManaCost ? 1.0 : 0.96)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.state.selfStatus.mana)
        }
        .disabled(!(isInputEnabled && viewModel.state.selfStatus.mana >= viewModel.attackManaCost))
        .accessibilityLabel(Text("ファイヤーボール"))
        .accessibilityHint(Text("MPを消費してファイヤーボールを放ちます"))
    }

    // Guard/SpecialはUIから除去

    private func viewModelPhaseText() -> String? {
        switch viewModelPhase {
        case .idle: return "準備中…"
        case .ready: return "接続中…"
        case .inputting: return nil
        case .resolving: return "解決中…"
        case .result(let r):
            switch r { case .win: return "勝利！"; case .lose: return "敗北…" }
        }
    }

    // hpRowはPlayerStatusViewへ統一しました

    // MARK: - Subviews

    private var runningDebug: some View {
        VStack(spacing: 4) {
            Text(viewModel.isRunning ? "走行中" : "待機中")
                .font(.title2).bold()
                .foregroundStyle(viewModel.isRunning ? .green : .secondary)
            if let rate = viewModel.stepRatePerSec {
                Text(String(format: "(%.1f 歩/秒)", rate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("走行ON中はMPが毎秒+3回復")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(viewModel.isRunning ? "走行中。MP回復中" : "待機中"))
    }

    private var permissionBanner: some View {
        VStack(spacing: 8) {
            Text("モーション権限が必要です")
                .font(.headline)
            Text("設定 > プライバシー > モーションとフィットネス で有効にしてください。")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            #if canImport(UIKit)
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.bordered)
            #endif
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("モーション権限が必要です。設定を開く。"))
    }
}

#if DEBUG
struct BattleView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { BattleView() }
    }
}
#endif

extension BattleResult: Identifiable {
    var id: String { self == .win ? "win" : "lose" }
}

// MARK: - Run Status Indicator

private struct RunStatusIndicator: View {
    let isRunning: Bool
    let rate: Double?
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isRunning {
                Circle().stroke(.green.opacity(0.35), lineWidth: 2)
                    .frame(width: 34, height: 34)
                    .scaleEffect(pulse ? 1.35 : 0.9)
                    .opacity(pulse ? 0.0 : 1.0)
                    .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false), value: pulse)
                Circle().stroke(.green.opacity(0.25), lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .scaleEffect(pulse ? 1.4 : 1.0)
                    .opacity(pulse ? 0.0 : 1.0)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
            }
            VStack(spacing: 6) {
                Image(systemName: isRunning ? "figure.run.circle.fill" : "person.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isRunning ? .green : .secondary)
                if let rate {
                    Text(String(format: "%.1f", rate))
                        .font(.caption2).bold()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("歩数レート"))
                        .accessibilityValue(Text(String(format: "%.1f", rate)))
                }
            }
        }
        .onAppear { pulse = isRunning }
        .onChange(of: isRunning) { running in pulse = running }
    }
}

// MARK: - Fireball Overlay (projectile + hit)

private struct FireballOverlay: View {
    let trigger: Int
    let onComplete: () -> Void
    @State private var progress: CGFloat = 0
    @State private var showHit = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !showHit {
                    // Projectile（豪華版）
                    let start = CGPoint(x: geo.size.width * 0.22, y: geo.size.height * 0.74)
                    let end = CGPoint(x: geo.size.width * 0.78, y: geo.size.height * 0.2)
                    let current = CGPoint(
                        x: start.x + (end.x - start.x) * progress,
                        y: start.y + (end.y - start.y) * progress
                    )
                    let dx = end.x - start.x
                    let dy = end.y - start.y
                    let angle = Angle(radians: Double(atan2(dy, dx)))

                    ZStack {
                        // Soft trail（2レイヤー）
                        ForEach(0..<2) { i in
                            let width = max(14, 90 * (1 - progress)) * (i == 0 ? 1.0 : 0.7)
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [.yellow.opacity(0.7), .orange.opacity(0.5), .red.opacity(0.2), .clear], startPoint: .trailing, endPoint: .leading))
                                .frame(width: width, height: 12)
                                .rotationEffect(angle)
                                .offset(x: -width * 0.45)
                                .blur(radius: i == 0 ? 1.2 : 2.0)
                                .blendMode(.plusLighter)
                        }

                        // After images（残光）
                        ForEach(1..<4) { t in
                            let bp = max(0, progress - CGFloat(t) * 0.08)
                            let ghost = CGPoint(
                                x: start.x + (end.x - start.x) * bp,
                                y: start.y + (end.y - start.y) * bp
                            )
                            Circle()
                                .fill(RadialGradient(colors: [.yellow, .orange.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: 16))
                                .frame(width: 18 - CGFloat(t) * 2, height: 18 - CGFloat(t) * 2)
                                .position(ghost)
                                .opacity(0.5 - Double(t) * 0.12)
                                .blendMode(.plusLighter)
                        }

                        // Core flame（ゆらぎ）
                        let coreSize = 22 + sin(progress * .pi * 2) * 2
                        Circle()
                            .fill(AngularGradient(gradient: Gradient(colors: [.yellow, .orange, .red, .orange, .yellow]), center: .center))
                            .frame(width: coreSize, height: coreSize)
                            .shadow(color: .orange.opacity(0.8), radius: 10)
                            .overlay(
                                Circle()
                                    .strokeBorder(.yellow.opacity(0.6), lineWidth: 1.2)
                                    .blur(radius: 0.6)
                            )
                            .blendMode(.plusLighter)
                            .position(current)

                        // Sparks（簡易）
                        ForEach(0..<12) { i in
                            let theta = Double(i) / 12.0 * 2 * Double.pi
                            let r = 6 + CGFloat(i % 3) * 3
                            Circle()
                                .fill(Color.yellow.opacity(0.9))
                                .frame(width: 3, height: 3)
                                .position(x: current.x + cos(theta) * r, y: current.y + sin(theta) * r)
                                .opacity(0.6)
                                .blendMode(.plusLighter)
                        }
                    }
                    .transition(.opacity)
                } else {
                    // Hit burst + shockwave + flash
                    ZStack {
                        HitBurst()
                            .frame(width: 110, height: 110)
                            .transition(.scale.combined(with: .opacity))
                        Shockwave()
                            .frame(width: 140, height: 140)
                    }
                    .position(x: geo.size.width * 0.78, y: geo.size.height * 0.2)
                    .overlay(
                        Rectangle()
                            .fill(Color.orange.opacity(0.2))
                            .blendMode(.plusLighter)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    )
                }
            }
            .onAppear { start() }
            .id(trigger)
        }
        .allowsHitTesting(false)
    }

    private func start() {
        progress = 0
        withAnimation(.easeOut(duration: 0.35)) {
            progress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            showHit = true
            withAnimation(.easeOut(duration: 0.15)) {}
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                onComplete()
                showHit = false
            }
        }
    }
}

private struct HitBurst: View {
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 1
    var body: some View {
        ZStack {
            ForEach(0..<6) { i in
                Circle()
                    .fill([Color.yellow, .orange, .red][i % 3].opacity(0.9))
                    .frame(width: 8, height: 8)
                    .offset(x: 0, y: -20)
                    .rotationEffect(.degrees(Double(i) / 6.0 * 360))
            }
            Circle()
                .strokeBorder(Color.orange.opacity(0.8), lineWidth: 2)
                .background(Circle().fill(Color.orange.opacity(0.2)))
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.15)) { scale = 1.2; opacity = 1 }
            withAnimation(.easeOut(duration: 0.15).delay(0.1)) { scale = 1.35; opacity = 0 }
        }
    }
}

private struct Shockwave: View {
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0.8
    var body: some View {
        Circle()
            .strokeBorder(LinearGradient(colors: [.yellow, .orange.opacity(0.6), .clear], startPoint: .center, endPoint: .top), lineWidth: 3)
            .shadow(color: .orange.opacity(0.6), radius: 6)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { scale = 1.4; opacity = 0 }
            }
    }
}
