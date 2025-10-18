import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

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

                MapView()
                    .tabItem {
                        Label("マップ", systemImage: "map.fill")
                    }
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
}
