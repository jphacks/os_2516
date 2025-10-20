
import SwiftUI

struct WaitingForOpponentView: View {
    @StateObject private var viewModel: WaitingForOpponentViewModel
    @Environment(\.presentationMode) private var presentation

    init(sessionID: String, service: BattleService) {
        _viewModel = StateObject(wrappedValue: WaitingForOpponentViewModel(sessionID: sessionID, service: service))
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .scaleEffect(1.6)
            Text("対戦相手を待っています…")
                .font(.title2).bold()
            Text("他のプレイヤーが参加すると自動的に開始します")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let name = viewModel.opponentName {
                Text("相手: \(name)")
                    .font(.headline)
                    .padding(.top, 8)
            }

            Spacer()

            Button(role: .cancel) {
                Task {
                    await viewModel.cancel()
                    presentation.wrappedValue.dismiss()
                }
            } label: {
                Text("キャンセル")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
        }
        .padding()
        .onAppear { viewModel.onAppear() }
        // WaitingForOpponentViewModel will post a notification with the resolved session id when appropriate.
    }
}

extension Notification.Name {
    static let waitingDidResolve = Notification.Name("WaitingForOpponentDidResolve")
}

struct WaitingForOpponentView_Previews: PreviewProvider {
    static var previews: some View {
        WaitingForOpponentView(sessionID: "mock", service: ServiceFactory.makeBattleService())
    }
}
