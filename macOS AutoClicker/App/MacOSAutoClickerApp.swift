//
//  MacOSAutoClickerApp.swift
//  macOS AutoClicker
//
//  Application entry point. SwiftUI lifecycle, single main window.
//

import SwiftUI

@main
struct MacOSAutoClickerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") { appState.newProject() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Automation") {
                Button("Start") { appState.startAutomation() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Stop") { appState.stopAutomation() }
                    .keyboardShortcut(".", modifiers: .command)
            }
        }
    }
}
