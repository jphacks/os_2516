import SwiftUI

struct NearbyInteractionIndicator: View {
    let status: NearbyInteractionService.Status
    let reading: NearbyInteractionService.Reading?
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("近距離センサー")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let reading {
                VStack(alignment: .leading, spacing: 4) {
                    if let distance = reading.distanceMeters {
                        Text("距離: \(format(distance: distance))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("距離: 計測中…")
                            .font(.subheadline.weight(.semibold))
                    }

                    if let azimuthText = headingText(for: reading.azimuthRadians) {
                        Text("方向: \(azimuthText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("相手端末を検出すると距離と方向を表示します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .padding(.horizontal, 12)
    }

    private var statusText: String {
        switch status {
        case .idle: return "待機中"
        case .unsupported: return "非対応"
        case .unauthorized: return "未許可"
        case .waitingForPeer: return "相手待ち"
        case .running: return "測位中"
        case .suspended: return "停止中"
        case .invalidated: return "再接続が必要"
        }
    }

    private var statusColor: Color {
        if let errorMessage, !errorMessage.isEmpty {
            return .red
        }
        switch status {
        case .running:
            return .green
        case .unsupported, .unauthorized, .invalidated:
            return .red
        case .suspended:
            return .orange
        case .idle, .waitingForPeer:
            return .secondary
        }
    }

    private func format(distance: Double) -> String {
        if distance >= 5 {
            return String(format: "%.1f m", distance)
        } else if distance >= 1 {
            return String(format: "%.2f m", distance)
        } else {
            return String(format: "%.0f cm", distance * 100)
        }
    }

    private func headingText(for radians: Double?) -> String? {
        guard let radians else { return nil }
        let degrees = (radians * 180 / .pi).truncatingRemainder(dividingBy: 360)
        let normalized = degrees < 0 ? degrees + 360 : degrees
        let labels = ["北", "北北東", "北東", "東北東", "東", "東南東", "南東", "南南東",
                      "南", "南南西", "南西", "西南西", "西", "西北西", "北西", "北北西"]
        let index = Int((normalized + 11.25) / 22.5) % labels.count
        return "\(labels[index]) (\(Int(round(normalized)))°)"
    }
}

#if DEBUG
struct NearbyInteractionIndicator_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NearbyInteractionIndicator(status: .running,
                                       reading: .init(distanceMeters: 1.32,
                                                      azimuthRadians: .pi / 4,
                                                      elevationRadians: 0),
                                       errorMessage: nil)
            NearbyInteractionIndicator(status: .waitingForPeer, reading: nil, errorMessage: nil)
            NearbyInteractionIndicator(status: .suspended, reading: nil, errorMessage: "相手の信号を待っています…")
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .background(Color.black.opacity(0.6))
    }
}
#endif
