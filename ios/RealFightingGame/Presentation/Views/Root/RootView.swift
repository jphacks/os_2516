import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        TabView {
            BattleView()
                .tabItem {
                    Label("ホーム", systemImage: "house.fill")
                }

            if #available(iOS 17.0, *) {
                MapView(
                    service: container.mapService,
                    locationService: container.locationService
                )
                    .tabItem { Label("マップ", systemImage: "map.fill") }
            } else {
                Text("iOS 17 以上でマップ表示に対応")
                    .tabItem { Label("マップ", systemImage: "map.fill") }
            }
        }
    }
}

#Preview {
    RootView().environmentObject(AppContainer(useMock: true))
}
