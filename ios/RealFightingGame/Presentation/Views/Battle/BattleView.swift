import SwiftUI

struct BattleView: View {
    @StateObject private var viewModel: BattleViewModel
    @State private var presentedResult: BattleResult?

    init(sessionID: String = "mock", service: BattleService = ServiceFactory.makeBattleService()) {
        _viewModel = StateObject(wrappedValue: BattleViewModel(sessionID: sessionID, service: service))
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                hpRow(title: viewModel.state.selfStatus.displayName,
                      hp: viewModel.state.selfStatus.hp,
                      max: viewModel.state.selfStatus.maxHp,
                      tint: .green)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(viewModel.state.selfStatus.displayName) のHP"))
                .accessibilityValue(Text("\(viewModel.state.selfStatus.hp) / \(viewModel.state.selfStatus.maxHp)"))
                hpRow(title: viewModel.state.opponentStatus.displayName,
                      hp: viewModel.state.opponentStatus.hp,
                      max: viewModel.state.opponentStatus.maxHp,
                      tint: .red)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(viewModel.state.opponentStatus.displayName) のHP"))
                .accessibilityValue(Text("\(viewModel.state.opponentStatus.hp) / \(viewModel.state.opponentStatus.maxHp)"))
            }
            .padding(.horizontal)

            gauges

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

            actions
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onChange(of: viewModelPhase) { phase in
            if case .result(let r) = phase { presentedResult = r }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
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

    private var gauges: some View {
        VStack(spacing: 8) {
            LabeledContent("Guard") {
                ProgressView(value: viewModel.state.runEnergy, total: 1)
                    .tint(.blue)
                    .frame(width: 160)
            }
            LabeledContent("Special") {
                ProgressView(value: viewModel.state.chantProgress, total: 1)
                    .tint(.orange)
                    .frame(width: 160)
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }

    private var actions: some View {
        Group {
            if hSize == .regular {
                HStack { attackButton; guardButton; specialButton }
            } else {
                VStack { attackButton; HStack { guardButton; specialButton } }
            }
        }
    }

    private var attackButton: some View {
        Button {
            viewModel.attackTapped()
        } label: {
            Text("Attack").font(.title3).bold()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isInputEnabled)
        .accessibilityLabel(Text("攻撃"))
        .accessibilityHint(Text("相手に攻撃します"))
    }

    private var guardButton: some View {
        Button("Guard") { viewModel.guardTapped() }
            .buttonStyle(.bordered)
            .disabled(!isInputEnabled)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text("ガード"))
            .accessibilityHint(Text("未実装"))
    }

    private var specialButton: some View {
        Button("Special") { viewModel.specialTapped() }
            .buttonStyle(.bordered)
            .disabled(!(isInputEnabled && isSpecialAvailable))
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text("必殺"))
            .accessibilityHint(Text("チャージが満タンで使用可能"))
    }

    private var isSpecialAvailable: Bool { viewModel.state.chantProgress >= 1.0 }

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

    private func hpRow(title: String, hp: Int, max: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("HP: \(hp)/\(max)")
            }
            ProgressView(value: Double(hp), total: Double(max))
                .tint(tint)
        }
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
