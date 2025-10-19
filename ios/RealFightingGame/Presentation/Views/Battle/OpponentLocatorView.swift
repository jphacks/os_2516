import SwiftUI

struct OpponentLocatorView: View {
    let telemetry: BattleTelemetry

    private var freshnessColor: Color {
        let age = Date().timeIntervalSince(telemetry.lastUpdate)
        if age < 1.5 { return .green }
        if age < 4.0 { return .yellow }
        return .gray
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 8) {
                // Arrow indicating heading
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 64, height: 64)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(Angle(degrees: telemetry.headingDegrees))
                        .accessibilityLabel(Text("相手方位"))
                }

                // Distance
                Text(distanceText(meters: telemetry.distanceMeters))
                    .font(.headline)
                    .bold()
                    .foregroundStyle(.white)

                // freshness
                Text(freshnessText())
                    .font(.caption)
                    .foregroundColor(freshnessColor)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 6)
            .frame(maxWidth: 200)
            // position near bottom-right corner with safe padding
            .position(x: geo.size.width * 0.82, y: geo.size.height * 0.88)
        }
        .allowsHitTesting(false)
    }

    private func distanceText(meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else {
            return String(format: "%.1f km", meters / 1000.0)
        }
    }

    private func freshnessText() -> String {
        let age = Date().timeIntervalSince(telemetry.lastUpdate)
        if age < 1.5 { return "サーバー接続OK" }
        if age < 4.0 { return "更新: やや古い" }
        return "更新: 古い"
    }
}

#if DEBUG
struct OpponentLocatorView_Previews: PreviewProvider {
    static var previews: some View {
        OpponentLocatorView(telemetry: .init(distanceMeters: 12.3, headingDegrees: 45, lastUpdate: Date()))
            .frame(width: 320, height: 240)
    }
}
#endif
