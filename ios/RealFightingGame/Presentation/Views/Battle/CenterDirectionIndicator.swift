import SwiftUI

struct CenterDirectionIndicator: View {
    let heading: Double
    let freshnessAge: TimeInterval

    private var opacityForAge: Double {
        if freshnessAge < 1.5 { return 1.0 }
        if freshnessAge < 4.0 { return 0.92 }
        return 0.6
    }

    var body: some View {
        ZStack {
            // rune outer circle
            Circle()
                .stroke(LinearGradient(colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                .frame(width: 200, height: 200)
                .shadow(color: Color.purple.opacity(0.18), radius: 12)

            // inner glowing disc
            Circle()
                .fill(RadialGradient(gradient: Gradient(colors: [Color.black.opacity(0.4), Color.black.opacity(0.15)]), center: .center, startRadius: 8, endRadius: 80))
                .frame(width: 120, height: 120)

            // glyph/arrow
            ZStack {
                // rotating rune ring
                Circle()
                    .stroke(AngularGradient(gradient: Gradient(colors: [Color.purple, Color.blue, Color.cyan, Color.purple]), center: .center), lineWidth: 3)
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(heading / 4))
                    .blendMode(.plusLighter)

                Image(systemName: "arrow.up")
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(LinearGradient(colors: [Color.white, Color.yellow.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                    .rotationEffect(Angle(degrees: heading))
                    .shadow(color: Color.blue.opacity(0.35), radius: 10)
            }
            .frame(width: 120, height: 120)
        }
        .frame(width: 240, height: 240)
        .opacity(opacityForAge)
        .allowsHitTesting(false)
    }
}

#if DEBUG
struct CenterDirectionIndicator_Previews: PreviewProvider {
    static var previews: some View {
        CenterDirectionIndicator(heading: 45, freshnessAge: 0.3)
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.gray)
    }
}
#endif
