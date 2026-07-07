//
//  AppState.swift
//  macOS AutoClicker
//
//  Root observable state. Stub now — real model wiring lands in Phase 2+.
//  Methods are placeholders so the @main command menu compiles.
//

import Foundation
import SwiftUI
import KeyboardShortcuts

@MainActor
final class AppState: ObservableObject {
    @Published var automationRunning: Bool = false

    func newProject() {
        // Phase 2: create empty project in App Support, select it.
    }

    func startAutomation() {
        // Phase 3: hand off to AutomationEngine.
        automationRunning = true
    }

    func stopAutomation() {
        automationRunning = false
    }
}

// Declare the global hotkey names used by KeyboardShortcuts.Name extensions.
// The actual recorder UI lands in Phase 4.
extension KeyboardShortcuts.Name {
    static let toggleAutomation = KeyboardShortcuts.Name("toggleAutomation")
}
