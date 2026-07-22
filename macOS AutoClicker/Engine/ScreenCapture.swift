//
//  ScreenCapture.swift
//  macOS AutoClicker
//
//  Window enumeration + capture for all four TargetSpec variants.
//
//  Capture path:
//    macOS 14+ → ScreenCaptureKit (SCScreenshotManager.captureImage with
//                an SCContentFilter that excludes this app's own windows)
//    macOS 13  → CGWindowList (window-array form, filtering out our PID)
//
//  Window enumeration:
//    macOS 14+ → SCShareableContent.current (async)
//    macOS 13  → CGWindowListCopyWindowInfo (synchronous)
//
//  Both paths produce the same `CapturedWindow` and `CGImage` types so the
//  rest of the engine doesn't care which was used.
//

import AppKit
import CoreGraphics
import Foundation
#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

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

    // MARK: - Permission probe

    /// True if this process can see other apps' windows (TCC Screen Recording).
    static var hasScreenRecordingPermission: Bool {
        // Non-prompting status check. CGPreflightScreenCaptureAccess reports
        // whether Screen Recording is granted WITHOUT capturing or triggering
        // the system prompt. (The old CGWindowListCreateImage probe re-fired the
        // "wants to record your screen" dialog on every call under macOS 14+.)
        CGPreflightScreenCaptureAccess()
    }

    // MARK: - Window enumeration

    /// Enumerate windows suitable for picking. Skips layer≠0 (menu bar,
    /// dock), tiny windows (<2px), and our own process.
    /// Uses ScreenCaptureKit on 14+, CGWindowList on 13.
    static func listWindows(excludingOwnPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> [CapturedWindow] {
        if #available(macOS 14.0, *) {
            // Synchronous wrapper around the async SCShareableContent API.
            // The blocking is acceptable here because listWindows is called
            // from user-initiated actions (Refresh button, picker open).
            if let sc = syncShareableContent() {
                return convert(sc: sc, excludingOwnPID: excludingOwnPID)
            }
            // Fall through to CGWindowList if SCK fails (e.g., no permission).
        }
        return listWindowsCGWindowList(excludingOwnPID: excludingOwnPID)
    }

    /// Legacy CGWindowList path — used on macOS 13 and as SCK fallback.
    private static func listWindowsCGWindowList(excludingOwnPID: pid_t) -> [CapturedWindow] {
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

            if layer != 0 { continue }
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

    /// Synchronous wrapper for `SCShareableContent.current` (async).
    /// Uses a locked box so the Task can safely hand the result back.
    @available(macOS 14.0, *)
    private static func syncShareableContent() -> SCShareableContent? {
        let box = ResultBox<SCShareableContent?>()
        let semaphore = DispatchSemaphore(value: 0)
        Task { @Sendable in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                box.set(content)
            } catch {
                box.set(nil)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return box.get() ?? nil
    }

    /// Map SCShareableContent → [CapturedWindow], filtering like the CG path.
    @available(macOS 14.0, *)
    private static func convert(sc: SCShareableContent, excludingOwnPID: pid_t) -> [CapturedWindow] {
        var out: [CapturedWindow] = []
        for w in sc.windows {
            let frame = w.frame
            if frame.width <= 1 || frame.height <= 1 { continue }
            let app = w.owningApplication
            let pid = app?.processID ?? 0
            if pid == excludingOwnPID { continue }
            let owner = app?.applicationName ?? ""
            out.append(CapturedWindow(
                windowID: w.windowID,
                ownerName: owner,
                windowName: w.title ?? "",
                frame: frame,
                ownerPID: pid,
                isOnScreen: true
            ))
        }
        return out
    }

    // MARK: - Target resolution

    /// Resolve a `TargetSpec` to a concrete `CapturedWindow`.
    static func resolveWindow(for spec: TargetSpec) -> CapturedWindow? {
        let windows = listWindows()
        switch spec {
        case .iphoneMirroring:
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
            if windowID != 0 {
                for w in windows where w.windowID == windowID { return w }
            }
            for w in windows where w.ownerName.lowercased() == owner.lowercased() {
                return w
            }
            for w in windows where w.ownerName.lowercased().contains(owner.lowercased()) {
                return w
            }
            return nil

        case .region, .fullScreen:
            return nil
        }
    }

    static func resolveWindow(compositeKey: String) -> CapturedWindow? {
        let parts = compositeKey.split(separator: "::", maxSplits: 2).map(String.init)
        guard parts.count == 3, let wid = CGWindowID(parts[0]) else { return nil }
        return resolveWindow(for: .window(owner: parts[1], windowID: wid))
    }

    // MARK: - Captures

    /// Capture a window by ID. Uses ScreenCaptureKit on 14+, CGWindowList
    /// on 13 (or if SCK fails at runtime).
    static func captureWindow(_ window: CapturedWindow) -> CGImage? {
        if window.isEntireScreen {
            return CGWindowListCreateImage(
                .infinite, [.optionOnScreenOnly], kCGNullWindowID, [.boundsIgnoreFraming]
            )
        }
        // Try ScreenCaptureKit first (modern, future-proof).
        if #available(macOS 14.0, *) {
            if let image = captureWindowSCK(windowID: window.windowID) {
                return image
            }
            // Fall through to CGWindowList on SCK failure.
        }
        return CGWindowListCreateImage(
            .null, [.optionIncludingWindow], window.windowID, [.boundsIgnoreFraming]
        )
    }

    /// Capture a screen region, EXCLUDING our own app's windows so the
    /// floating clicker UI never pollutes the captured frame.
    ///
    /// macOS 14+: capture the display that contains `rect` with an
    /// `SCContentFilter` that excludes our own `SCRunningApplication`, then
    /// crop the resulting full-display `CGImage` to `rect` (scaled by the
    /// display's backing factor, since SCK returns pixels at retina
    /// resolution while `rect` is in points).
    ///
    /// macOS 13: build a `CGWindowID` array from on-screen windows whose
    /// owner PID isn't ours, then composite them via
    /// `CGImage(windowListFromArray:...)`.
    static func captureRegion(_ rect: CGRect) -> CGImage? {
        if #available(macOS 14.0, *) {
            if let image = captureRegionExcludingOwnApp(rect: rect) {
                return image
            }
            // Fall through to CGWindowList on SCK failure.
        }
        return captureRegionCGArray(rect: rect)
    }

    /// Capture a whole display, EXCLUDING our own app's windows.
    static func captureFullScreen(_ displayID: CGDirectDisplayID) -> CGImage? {
        if #available(macOS 14.0, *) {
            if let image = captureFullScreenSCK(displayID: displayID) {
                return image
            }
        }
        return captureFullScreenCGArray(displayID: displayID)
    }

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

    // MARK: - ScreenCaptureKit capture paths

    /// Capture a single window via SCScreenshotManager (macOS 14+).
    /// Returns nil if ScreenCaptureKit can't produce an image for any reason
    /// (permission denied, window closed, etc.) — caller falls back to CG.
    @available(macOS 14.0, *)
    private static func captureWindowSCK(windowID: CGWindowID) -> CGImage? {
        guard let content = syncShareableContent() else { return nil }
        guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        return captureImageSCK(filter: filter)
    }

    /// Find our own `SCRunningApplication` inside a shareable-content
    /// snapshot by matching `Bundle.main.bundleIdentifier`. Returns nil when
    /// the bundle ID is unset or our app isn't present in the snapshot.
    @available(macOS 14.0, *)
    private static func ownApplication(in content: SCShareableContent) -> SCRunningApplication? {
        guard let bid = Bundle.main.bundleIdentifier else { return nil }
        return content.applications.first { $0.bundleIdentifier == bid }
    }

    /// Find the `SCDisplay` whose `displayID` matches the given
    /// `CGDirectDisplayID`. Returns nil if not present in the snapshot.
    @available(macOS 14.0, *)
    private static func scDisplay(matching displayID: CGDirectDisplayID, in content: SCShareableContent) -> SCDisplay? {
        content.displays.first { $0.displayID == displayID }
    }

    /// macOS 14+ full-screen capture excluding our own app's windows.
    /// Builds `SCContentFilter(display:excludingApplications:exceptingWindows:)`
    /// with our `SCRunningApplication`, then runs it through the shared
    /// `captureImageSCK(filter:)` helper.
    @available(macOS 14.0, *)
    private static func captureFullScreenSCK(displayID: CGDirectDisplayID) -> CGImage? {
        guard let content = syncShareableContent(),
              let scDisplay = scDisplay(matching: displayID, in: content) else { return nil }
        let excluded = ownApplication(in: content).map { [$0] } ?? []
        let filter = SCContentFilter(
            display: scDisplay,
            excludingApplications: excluded,
            exceptingWindows: []
        )
        return captureImageSCK(filter: filter)
    }

    /// macOS 14+ region capture excluding our own app's windows. Captures the
    /// display that owns `rect` with the exclusion filter, then crops the
    /// returned full-display image down to `rect`.
    ///
    /// Scale handling: SCK returns pixels at the display's backing resolution
    /// (retina = 2x the points that `rect` is expressed in). We compute the
    /// real backing scale as `image.width / displayBounds.width` and multiply
    /// every crop coordinate by it, so the crop lands on the right pixels
    /// regardless of retina/scaling/multi-display DPI differences.
    @available(macOS 14.0, *)
    private static func captureRegionExcludingOwnApp(rect: CGRect) -> CGImage? {
        // Resolve the CGDirectDisplayID that contains the largest portion of
        // rect, then map it to an SCDisplay inside the shareable snapshot.
        var did: CGDirectDisplayID = 0
        var count: UInt32 = 0
        CGGetDisplaysWithRect(rect, 1, &did, &count)
        guard count > 0, did != kCGNullDirectDisplay,
              let content = syncShareableContent(),
              let scDisplay = scDisplay(matching: did, in: content) else { return nil }

        let excluded = ownApplication(in: content).map { [$0] } ?? []
        let filter = SCContentFilter(
            display: scDisplay,
            excludingApplications: excluded,
            exceptingWindows: []
        )
        guard let fullImage = captureImageSCK(filter: filter) else { return nil }

        // Display origin in global coords, so we can shift rect into the
        // display's local space before scaling.
        let displayBounds = CGDisplayBounds(did)
        let localOriginX = rect.origin.x - displayBounds.origin.x
        let localOriginY = rect.origin.y - displayBounds.origin.y

        // Backing scale: retina displays report image.width == 2 * bounds.width.
        let scaleX = CGFloat(fullImage.width)  / displayBounds.width
        let scaleY = CGFloat(fullImage.height) / displayBounds.height

        let cropRect = CGRect(
            x: localOriginX * scaleX,
            y: localOriginY * scaleY,
            width:  rect.width  * scaleX,
            height: rect.height * scaleY
        )
        return fullImage.cropping(to: cropRect)
    }

    /// macOS 13 (and SCK-fallback) full-screen capture. Builds a `CGWindowID`
    /// array of every on-screen window whose owner PID isn't ours, then
    /// composites just those windows via the `CGImage(windowListFromArray:...)`
    /// initializer. Replaces the old `CGWindowListCreateImage` call which
    /// always included this app's floating window.
    private static func captureFullScreenCGArray(displayID: CGDirectDisplayID) -> CGImage? {
        let bounds = CGDisplayBounds(displayID)
        return captureCGArray(in: bounds)
    }

    /// macOS 13 (and SCK-fallback) region capture. Same PID-excluded window
    /// array approach as `captureFullScreenCGArray`, scoped to `rect`.
    private static func captureRegionCGArray(rect: CGRect) -> CGImage? {
        captureCGArray(in: rect)
    }

    /// Shared helper: composite every on-screen window whose owner PID isn't
    /// `getpid()` into a single image clipped to `bounds`.
    private static func captureCGArray(in bounds: CGRect) -> CGImage? {
        let ownPID = getpid()
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let windowIDs: [NSNumber] = raw.compactMap { w in
            let pid = (w[kCGWindowOwnerPID as String] as? Int32) ?? 0
            guard pid != ownPID else { return nil }
            let wid = (w[kCGWindowNumber as String] as? Int) ?? 0
            return wid == 0 ? nil : NSNumber(value: wid)
        }
        guard !windowIDs.isEmpty else { return nil }
        let cfArray = windowIDs as CFArray
        return CGImage(
            windowListFromArrayScreenBounds: bounds,
            windowArray: cfArray,
            imageOption: [.boundsIgnoreFraming]
        )
    }

    /// Shared SCK image-capture helper using a content filter.
    @available(macOS 14.0, *)
    private static func captureImageSCK(filter: SCContentFilter) -> CGImage? {
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        // Capture at NATIVE PIXEL resolution. The default configuration
        // returns a point-size (downscaled) frame, which would mismatch the
        // legacy CGWindowList captures and every stored reference image —
        // action x/y live in retina-pixel space.
        if #available(macOS 14.0, *) {
            let scale = CGFloat(filter.pointPixelScale)
            if filter.contentRect.width > 0, scale > 0 {
                config.width  = Int(filter.contentRect.width  * scale)
                config.height = Int(filter.contentRect.height * scale)
            }
        }
        let box = ResultBox<CGImage?>()
        let semaphore = DispatchSemaphore(value: 0)
        Task { @Sendable in
            do {
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config
                )
                box.set(image)
            } catch {
                box.set(nil)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return box.get() ?? nil
    }

    // MARK: - Bring to front

    @MainActor
    static func bringToFront(_ window: CapturedWindow) -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        guard let app = apps.first(where: { $0.processIdentifier == window.ownerPID }) else {
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

/// Locked single-value box for handing an async result back to a sync caller.
/// Used to wrap non-Sendable types (SCShareableContent, CGImage) when we
/// bridge an async Task into a synchronous DispatchSemaphore wait.
private final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    init() { stored = nil }
    func set(_ v: T) { lock.lock(); defer { lock.unlock() }; stored = v }
    func get() -> T? { lock.lock(); defer { lock.unlock() }; return stored }
}
