import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        if authViewModel.isAuthenticated {
            authenticatedView
        } else {
            AuthView()
        }
    }

    private var authenticatedView: some View {
        NavigationStack {
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

                StageListView(
                    mapService: container.mapService,
                    locationService: container.locationService
                )
                .tabItem { Label("ステージ", systemImage: "list.bullet") }
            }
            .navigationTitle("Real Fighting Game")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let user = authViewModel.currentUser {
                        Text(user.fullName.isEmpty ? user.email : user.fullName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("ログアウト") {
                        authViewModel.signOut()
                    }
                }
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AuthViewModel())
        .environmentObject(AppContainer(useMock: true))
}
