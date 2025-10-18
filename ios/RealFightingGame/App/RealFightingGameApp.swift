//
//  RealFightingGameApp.swift
//  RealFightingGame
//
//  Created by atnuhs on 2025/10/18.
//

import SwiftUI

@main
struct RealFightingGameApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
        }
    }
}
