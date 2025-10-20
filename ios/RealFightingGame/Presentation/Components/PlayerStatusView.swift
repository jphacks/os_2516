import SwiftUI

struct PlayerStatusView: View {
    let participant: BattleParticipant
    let accent: Color
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            Text(participant.displayName)
                .font(.headline)
                .foregroundStyle(.primary)
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)

            HStack(spacing: 12) {
                gemMeter(title: "HP",
                         value: Double(participant.hp),
                         total: Double(participant.maxHp),
                         tint: accent,
                         systemIcon: "heart.fill")
                gemMeter(title: "MP",
                         value: Double(participant.mana),
                         total: Double(participant.maxMana),
                         tint: .purple,
                         systemIcon: "bolt.fill")
            }
        }
        .padding(14)
        .background(
            LinearGradient(colors: [Color(.sRGB, red: 0.07, green: 0.04, blue: 0.06, opacity: 0.55), Color(.sRGB, red: 0.12, green: 0.07, blue: 0.09, opacity: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(LinearGradient(colors: [accent.opacity(0.9), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                .blendMode(.overlay)
        )
        .frame(maxWidth: 280, alignment: alignment == .leading ? .leading : .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(participant.displayName) のステータス"))
        .accessibilityValue(Text("HP \(participant.hp)/\(participant.maxHp)、MP \(participant.mana)/\(participant.maxMana)"))
    }

    private func labeledMeter(title: String,
                              value: Double,
                              total: Double,
                              tint: Color) -> some View {
        // fallback - kept for compatibility (not used)
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: value, total: total)
                .tint(tint)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: value)
        }
        .frame(width: 110)
    }

    private func gemMeter(title: String,
                          value: Double,
                          total: Double,
                          tint: Color,
                          systemIcon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: systemIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.6), radius: 4, x: 0, y: 1)
                Text(title)
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color.black.opacity(0.45), Color.black.opacity(0.18)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 14)

                // inner glossy fill
                let fraction = max(0, min(1, total > 0 ? value / total : 0))
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: CGFloat(110) * CGFloat(fraction), height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.6)
                            .blendMode(.overlay)
                    )
                    .shadow(color: tint.opacity(0.45), radius: 6, x: 0, y: 2)

                // highlight
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .frame(width: CGFloat(110) * CGFloat(fraction), height: 6)
                    .offset(y: -4)
                    .mask(RoundedRectangle(cornerRadius: 10).frame(width: CGFloat(110) * CGFloat(fraction), height: 6))
            }
            .frame(width: 110, height: 14)

            HStack {
                Text("\(Int(value))/\(Int(total))")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

#Preview {
    PlayerStatusView(participant: .mockSelf,
                     accent: .blue,
                     alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
}
