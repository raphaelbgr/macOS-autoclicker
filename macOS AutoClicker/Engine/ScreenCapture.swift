//
//  ScreenCapture.swift
//  macOS AutoClicker
//
//  Window enumeration + capture for all four TargetSpec variants.
//  Ported from src/screen_capture.py.
//
//  On macOS 13+, CGWindowList APIs are the stable backbone (matching the
//  Python app). ScreenCaptureKit is the modern streaming API but adds
//  async complexity without benefitting our poll-based matching loop, so
//  we stick with CGWindowListCreateImage — the same call the Python app
//  has been using reliably.
//

import AppKit
import CoreGraphics
import Foundation

/// Snapshot of a single on-screen window (the UI picker shows these).
struct CapturedWindow: Hashable, Identifiable, Sendable {
    var id: CGWindowID { windowID }
    let windowID: CGWindowID
    let ownerName: String
    let windowName: String
    let frame: CGRect       // global display coords
    let ownerPID: pid_t
    let isOnScreen: Bool

    var isEntireScreen: Bool { ownerName == "[Entire Screen]" }
}

enum ScreenCapture {
    /// True if this process can see other apps' windows (TCC Screen Recording).
    /// Mirrors Python `check_screen_recording_permission`.
    static var hasScreenRecordingPermission: Bool {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID
        ) as? [[String: Any]] else { return false }
        for w in list {
            let wid = (w[kCGWindowNumber as String] as? Int) ?? 0
            if wid > 0 {
                let image = CGWindowListCreateImage(
                    .null,
                    [.optionIncludingWindow],
                    CGWindowID(wid),
                    [.boundsIgnoreFraming]
                )
                return image != nil
            }
        }
        return false
    }

    /// Enumerate windows suitable for picking. Skips layer≠0 (menu bar,
    /// dock), tiny windows (<2px), and our own process. Mirrors
    /// Python `list_windows`.
    static func listWindows(excludingOwnPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> [CapturedWindow] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        var out: [CapturedWindow] = []
        for w in raw {
            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            let wname = (w[kCGWindowName as String] as? String) ?? ""
            let wid   = (w[kCGWindowNumber as String] as? Int) ?? 0
            let pid   = (w[kCGWindowOwnerPID as String] as? Int32) ?? 0
            let layer = (w[kCGWindowLayer as String] as? Int) ?? 0

            // Skip menu bar, dock, system overlays.
            if layer != 0 { continue }
            // Skip our own app's windows.
            if pid == excludingOwnPID { continue }

            guard let boundsDict = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width  = boundsDict["Width"],
                  let height = boundsDict["Height"] else { continue }
            if width <= 1 || height <= 1 { continue }

            let x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            out.append(CapturedWindow(
                windowID: CGWindowID(wid),
                ownerName: owner,
                windowName: wname,
                frame: CGRect(x: x, y: y, width: width, height: height),
                ownerPID: pid,
                isOnScreen: true
            ))
        }
        return out
    }

    /// Resolve a `TargetSpec` to a concrete `CapturedWindow` (for the
    /// `.window` / `.iphoneMirroring` cases). Returns nil if not found.
    /// Mirrors Python `find_target_window`.
    static func resolveWindow(for spec: TargetSpec) -> CapturedWindow? {
        let windows = listWindows()

        switch spec {
        case .iphoneMirroring:
            // Match "iPhone Mirroring" (or the bundle id) by owner name.
            for w in windows where w.ownerName.lowercased() == "iphone mirroring" {
                return w
            }
            for w in windows {
                let o = w.ownerName.lowercased()
                if o.contains("iphone mirroring") || o.contains("iphone") || o.contains("mirror") {
                    return w
                }
            }
            return nil

        case .window(let owner, let windowID):
            // Prefer the stable windowID when present.
            if windowID != 0 {
                for w in windows where w.windowID == windowID { return w }
            }
            // Fallback to exact owner name (case-insensitive).
            for w in windows where w.ownerName.lowercased() == owner.lowercased() {
                return w
            }
            // Then substring.
            for w in windows where w.ownerName.lowercased().contains(owner.lowercased()) {
                return w
            }
            return nil

        case .region, .fullScreen:
            return nil  // not window-based
        }
    }

    // MARK: - Captures

    /// Capture a window by ID. Mirrors Python `capture_window`.
    static func captureWindow(_ window: CapturedWindow) -> CGImage? {
        if window.isEntireScreen {
            return CGWindowListCreateImage(
                .infinite,
                [.optionOnScreenOnly],
                kCGNullWindowID,
                [.boundsIgnoreFraming]
            )
        }
        return CGWindowListCreateImage(
            .null,
            [.optionIncludingWindow],
            window.windowID,
            [.boundsIgnoreFraming]
        )
    }

    /// Capture a screen region (in global display coords).
    static func captureRegion(_ rect: CGRect) -> CGImage? {
        // CGWindowListCreateImage with a rect + OnScreenOnly captures every
        // visible window intersecting that rect, composited. This matches
        // what the user sees drawn inside the rectangle they drew.
        return CGWindowListCreateImage(
            rect,
            [.optionOnScreenOnly],
            kCGNullWindowID,
            [.boundsIgnoreFraming]
        )
    }

    /// Capture an entire display by ID.
    static func captureFullScreen(_ displayID: CGDirectDisplayID) -> CGImage? {
        let bounds = CGDisplayBounds(displayID)
        return CGWindowListCreateImage(
            bounds,
            [.optionOnScreenOnly],
            kCGNullWindowID,
            [.boundsIgnoreFraming]
        )
    }

    /// Convenience: capture whatever the spec points at.
    static func capture(for spec: TargetSpec, resolvedWindow: CapturedWindow?) -> CGImage? {
        switch spec {
        case .iphoneMirroring, .window:
            guard let w = resolvedWindow else { return nil }
            return captureWindow(w)
        case .region(let rect):
            return captureRegion(rect)
        case .fullScreen(let did):
            return captureFullScreen(did)
        }
    }

    /// Convenience: capture a window by composite key, mirroring the Python
    /// "ID::Owner::Name" lookup. Used for backward-compat on imports.
    static func resolveWindow(compositeKey: String) -> CapturedWindow? {
        let parts = compositeKey.split(separator: "::", maxSplits: 2).map(String.init)
        guard parts.count == 3, let wid = CGWindowID(parts[0]) else { return nil }
        return resolveWindow(for: .window(owner: parts[1], windowID: wid))
    }

    // MARK: - Bring to front

    /// Activate the window's owning application. Mirrors Python
    /// `bring_window_to_front`. Must be called on the main thread.
    @MainActor
    static func bringToFront(_ window: CapturedWindow) -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        guard let app = apps.first(where: { $0.processIdentifier == window.ownerPID }) else {
            // Fallback: AppleScript `tell application "Owner" to activate`.
            return activateViaAppleScript(window.ownerName)
        }
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        return app.isActive
    }

    private static func activateViaAppleScript(_ owner: String) -> Bool {
        let script = "tell application \"\(owner)\" to activate"
        let appleScript = NSAppleScript(source: script)
        return appleScript?.executeAndReturnError(nil) != nil
    }
}
