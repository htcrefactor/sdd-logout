//
//  LOGOUTApp.swift
//  LOGOUT
//
//  Created by Hyung-Taik Choi on 2026-11-07.
//

import SwiftUI
import LOGOUTCore

@main
struct LOGOUTApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: model.language.rawValue))
                .preferredColorScheme(.dark)
                .tint(LogoutPalette.cyan)
                .task { await model.bootstrap() }
        }
    }
}
