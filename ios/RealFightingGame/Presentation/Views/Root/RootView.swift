import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            BattleView()
                .tabItem {
                    Label("ホーム", systemImage: "house.fill")
                }

            MapView()
                .tabItem {
                    Label("マップ", systemImage: "map.fill")
                }
        }
    }
}

#Preview {
    RootView()
}
