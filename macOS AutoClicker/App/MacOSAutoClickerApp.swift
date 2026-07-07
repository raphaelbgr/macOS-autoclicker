//
//  MacOSAutoClickerApp.swift
//  macOS AutoClicker
//
//  Application entry point. SwiftUI lifecycle, single main window.
//

import SwiftUI
import KeyboardShortcuts

@main
struct MacOSAutoClickerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 650)
                .onAppear(perform: setupGlobalHotkey)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") { appState.newProject() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Import Project…") { appState.importProject() }
                Divider()
                Button("Close Window") { NSApp.keyWindow?.close() }
                    .keyboardShortcut("w", modifiers: .command)
            }

            CommandMenu("Automation") {
                Button("Start") { appState.startAutomation() }
                    .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.automationRunning)
                Button("Stop") { appState.stopAutomation() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!appState.automationRunning)
                Divider()
                Button("Add Action") { appState.presentAddAction() }
                    .keyboardShortcut(.return, modifiers: [.command])
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .appInfo) {
                Button("About macOS OCR AutoClicker") { openAbout() }
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 800)

        Settings {
            SettingsView(appState: appState)
        }
    }

    private func setupGlobalHotkey() {
        KeyboardShortcuts.onKeyUp(for: .toggleAutomation) {
            if appState.automationRunning {
                appState.stopAutomation()
            } else {
                appState.startAutomation()
            }
        }
    }

    private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func openAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "macOS OCR AutoClicker",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1",
            .credits: "by Raphael BGR · github.com/raphaelbgr"
        ])
    }
}
