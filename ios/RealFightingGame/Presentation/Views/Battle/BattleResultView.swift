import SwiftUI

struct BattleResultView: View {
    let result: BattleResult
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(resultTitle)
                .font(.largeTitle).bold()
            HStack(spacing: 12) {
                Button("再戦") { onRetry() }
                    .buttonStyle(.borderedProminent)
                Button("閉じる") { onClose() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .presentationDetents([.medium])
    }

    private var resultTitle: String {
        switch result { case .win: return "勝利"; case .lose: return "敗北" }
    }
}

#if DEBUG
struct BattleResultView_Previews: PreviewProvider {
    static var previews: some View {
        BattleResultView(result: .win, onRetry: {}, onClose: {})
    }
}
#endif

