import SwiftUI

struct OpponentLocatorView: View {
    let telemetry: BattleTelemetry

    @State private var expanded: Bool = false
    @State private var lastHeading: Double = 0

    private var freshnessColor: Color {
        let age = Date().timeIntervalSince(telemetry.lastUpdate)
        if age < 1.5 { return .green }
        if age < 4.0 { return .yellow }
        return .gray
    }

    var body: some View {
        Group {
            if expanded {
                expandedView
            } else {
                collapsedView
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: expanded)
        .onChange(of: telemetry.headingDegrees) { new in
            // smooth rotation by updating lastHeading with animation
            withAnimation(.interpolatingSpring(stiffness: 120, damping: 14)) {
                lastHeading = new
            }
        }
        .onAppear { lastHeading = telemetry.headingDegrees }
        .accessibilityElement(children: .combine)
    }

    private var collapsedView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(freshnessColor)
                .frame(width: 12, height: 12)
            Text(distanceText(meters: telemetry.distanceMeters))
                .font(.subheadline).bold()
                .foregroundColor(.white)
            Image(systemName: "chevron.up.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZStack {
                LinearGradient(colors: [Color(.sRGB, red: 0.04, green: 0.03, blue: 0.05, opacity: 0.6), Color(.sRGB, red: 0.09, green: 0.06, blue: 0.08, opacity: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 24)
                    .stroke(LinearGradient(colors: [Color.yellow.opacity(0.12), Color.white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
        , in: Capsule())
        .shadow(color: Color.black.opacity(0.45), radius: 10, x: 0, y: 4)
        .onTapGesture { expanded.toggle() }
    }

    private var expandedView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 84, height: 84)
                Image(systemName: "arrow.up")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.white, .yellow], startPoint: .top, endPoint: .bottom))
                    .rotationEffect(Angle(degrees: lastHeading))
                    .accessibilityLabel(Text("相手方位"))
            }

            VStack(spacing: 4) {
                Text(distanceText(meters: telemetry.distanceMeters))
                    .font(.title3).bold().foregroundColor(.white)
                Text(freshnessText())
                    .font(.caption).foregroundColor(freshnessColor)
            }

            Button(action: { expanded.toggle() }) {
                Text("閉じる")
                    .font(.caption).bold()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [Color.purple.opacity(0.95), Color.blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule()
                    )
            }
        }
        .padding(12)
        .background(
            ZStack {
                Color.black.opacity(0.35)
                RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.03), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 6)
        .frame(maxWidth: 240)
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

// Simple blur wrapper for better background on older iOS versions
import UIKit
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView { UIVisualEffectView(effect: UIBlurEffect(style: style)) }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

#if DEBUG
struct OpponentLocatorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            OpponentLocatorView(telemetry: .init(distanceMeters: 12.3, headingDegrees: 45, lastUpdate: Date()))
                .previewLayout(.sizeThatFits)
                .padding()
        }
    }
}
#endif
