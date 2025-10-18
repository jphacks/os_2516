import SwiftUI

struct PlayerStatusView: View {
    let participant: BattleParticipant
    let accent: Color
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            Text(participant.displayName)
                .font(.headline)
            HStack(spacing: 12) {
                labeledMeter(title: "HP",
                             value: Double(participant.hp),
                             total: Double(participant.maxHp),
                             tint: accent)
                labeledMeter(title: "魔素",
                             value: Double(participant.mana),
                             total: Double(participant.maxMana),
                             tint: .purple)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .frame(maxWidth: 280, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func labeledMeter(title: String,
                              value: Double,
                              total: Double,
                              tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: value, total: total)
                .tint(tint)
        }
        .frame(width: 110)
    }
}

#Preview {
    PlayerStatusView(participant: .mockSelf,
                     accent: .blue,
                     alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
}
