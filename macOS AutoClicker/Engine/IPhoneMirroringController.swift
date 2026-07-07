//
//  IPhoneMirroringController.swift
//  macOS AutoClicker
//
//  Drives the iPhone Mirroring app's View-menu commands via AppleScript.
//  Ported from src/iphone_control.py.
//
//  Only used when the project target is .iphoneMirroring. All calls go
//  through `osascript` via AppleEvent descriptors so they honor the
//  NSAppleEventsUsageDescription entitlement.
//

import AppKit
import Foundation

/// High-level iPhone Mirroring menu commands.
enum IPhoneMirroringCommand: String {
    case home          // "Home Screen"
    case appSwitcher   // "App Switcher"
    case spotlight     // "Spotlight"

    /// Menu item name as it appears in iPhone Mirroring's View menu.
    var menuItemName: String {
        switch self {
        case .home:         return "Home Screen"
        case .appSwitcher:  return "App Switcher"
        case .spotlight:    return "Spotlight"
        }
    }
}

enum IPhoneMirroringController {

    /// Process name used for AppleScript targeting.
    static let processName = "iPhone Mirroring"

    // MARK: - Public API

    /// Activate iPhone Mirroring (bring to front).
    @discardableResult
    static func activate() -> Bool {
        runAppleScript("tell application \"\(processName)\" to activate")
    }

    /// Trigger a View-menu command (Home / App Switcher / Spotlight).
    @discardableResult
    static func sendCommand(_ command: IPhoneMirroringCommand) -> Bool {
        let script = """
        tell application "System Events"
            tell process "\(processName)"
                click menu item "\(command.menuItemName)" of menu 1 of menu bar item "View" of menu bar 1
            end tell
        end tell
        """
        return runAppleScript(script)
    }

    /// Type text via iPhone Mirroring (used to launch an app via Spotlight).
    /// If `pressReturn` is true, sends Return at the end.
    @discardableResult
    static func typeText(_ text: String, pressReturn: Bool = true) -> Bool {
        // Sanitize for AppleScript string literal: escape double quotes and backslashes.
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        var script = "tell application \"System Events\" to keystroke \"\(escaped)\""
        if pressReturn {
            script += "\ntell application \"System Events\" to keystroke return"
        }
        return runAppleScript(script)
    }

    // MARK: - Internals

    /// Run an AppleScript string and return true on success.
    /// Uses NSAppleScript (in-process, no fork to /usr/bin/osascript).
    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        // NSAppleScript must be invoked on the main thread.
        if Thread.isMainThread {
            return runAppleScriptInline(source)
        }
        var result = false
        DispatchQueue.main.sync { result = runAppleScriptInline(source) }
        return result
    }

    private static func runAppleScriptInline(_ source: String) -> Bool {
        let appleScript = NSAppleScript(source: source)
        var errorInfo: NSDictionary?
        appleScript?.executeAndReturnError(&errorInfo)
        return errorInfo == nil
    }
}
