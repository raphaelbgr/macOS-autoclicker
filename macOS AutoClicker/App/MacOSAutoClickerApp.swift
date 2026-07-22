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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                Button("Export Project…") { appState.exportProject() }
                    .disabled(appState.selectedProjectName == nil)
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
        }
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
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-uitest") }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}
