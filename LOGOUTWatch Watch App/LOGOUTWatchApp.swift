//
//  LOGOUTWatchApp.swift
//  LOGOUTWatch Watch App
//
//  Created by Hyung-Taik Choi on 2026-11-07.
//

import SwiftUI
import HealthKit
import WatchKit

@main
struct LOGOUTWatch_Watch_AppApp: App {
    @WKExtensionDelegateAdaptor(WatchExtensionDelegate.self) var extensionDelegate
    @StateObject private var model = WatchRunModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}

final class WatchExtensionDelegate: NSObject, WKExtensionDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in WatchRunModel.shared.handleWorkoutLaunch() }
    }

    func handleActiveWorkoutRecovery() {
        Task { @MainActor in WatchRunModel.shared.handleActiveRecovery() }
    }
}
