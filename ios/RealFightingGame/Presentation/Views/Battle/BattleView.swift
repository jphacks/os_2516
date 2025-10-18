import SwiftUI

struct BattleView: View {
    @StateObject private var viewModel = BattleViewModel()

    var body: some View {
        VStack(spacing: 32) {
            telemetryCard
            Spacer()
            actionPanel
        }
        .padding(.init(top: 120, leading: 80, bottom: 120, trailing: 80))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(.systemBackground))
        .overlay(alignment: .topLeading) {
            PlayerStatusView(participant: viewModel.state.opponentStatus,
                             accent: .red,
                             alignment: .leading)
                .padding()
        }
        .overlay(alignment: .bottomTrailing) {
            PlayerStatusView(participant: viewModel.state.selfStatus,
                             accent: .blue,
                             alignment: .trailing)
                .padding()
        }
    }

    private var telemetryCard: some View {
        VStack(spacing: 12) {
            Text("敵との距離 \(String(format: "%.1f", viewModel.state.telemetry.distanceMeters))m")
                .font(.title3)
            Text("方位 \(Int(viewModel.state.telemetry.headingDegrees))°")
                .foregroundStyle(.secondary)
            Text("最終更新 \(viewModel.state.telemetry.lastUpdate, style: .time)")
                .font(.footnote)
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private var actionPanel: some View {
        VStack(spacing: 16) {
            ProgressView(value: viewModel.state.chantProgress) {
                Text("詠唱進行度")
            }
            .tint(.orange)

            ProgressView(value: viewModel.state.runEnergy) {
                Text("走行エネルギー")
            }
            .tint(.green)

            Button {
                viewModel.simulateTick()
            } label: {
                Text("詠唱開始")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(maxWidth: 420)
    }
}

#Preview {
    BattleView()
}
