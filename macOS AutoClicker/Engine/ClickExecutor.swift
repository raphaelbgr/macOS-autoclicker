//
//  ClickExecutor.swift
//  macOS AutoClicker
//
//  Synthesizes mouse events via CGEvent. Ported from src/click_engine.py.
//  Faithful to the Python behavior:
//    - single / double / longPress / swipe via kCGHIDEventTap
//    - "background" mode captures and restores cursor position
//    - longPress and swipe are interruptible via the cancellation handle
//

import AppKit
import CoreGraphics

/// Posts synthetic mouse events. Each method takes ABSOLUTE screen coordinates.
/// Window-relative → absolute conversion happens in AutomationEngine before
/// calling into here.
final class ClickExecutor: @unchecked Sendable {
    private let postTap: CGEventTapLocation = .cgSessionEventTap
    private var isActive: Bool = true

    // MARK: - Permissions

    static var hasPostEventPermission: Bool {
        // CGPreflightPostEventAccess returns Bool on modern macOS SDKs.
        return CGPreflightPostEventAccess()
    }

    /// Whether the process is trusted for Accessibility. This reflects the exact
    /// toggle the user flips in System Settings → Privacy & Security → Accessibility
    /// and updates live within the running process — unlike the event-posting
    /// preflight, which can lag a fresh grant until relaunch. Used by the
    /// onboarding so the status matches what the user actually granted.
    static var hasAccessibilityPermission: Bool {
        return AXIsProcessTrusted()
    }

    @discardableResult
    static func requestPostEventPermission() -> Bool {
        // Triggers the macOS Accessibility prompt if not yet granted.
        return CGRequestPostEventAccess()
    }

    // MARK: - Active flag (matches Python activate/deactivate)

    func activate()   { isActive = true }
    func deactivate() { isActive = false }

    // MARK: - Click at absolute coordinates

    /// Mirrors Python `execute_at_absolute`. The main entry point for clicks
    /// after AutomationEngine has resolved window-relative → absolute coords.
    @discardableResult
    func clickAtAbsolute(
        _ absX: Int, _ absY: Int,
        type: ClickType,
        durationMs: Int = 100,
        background: Bool = false,
        cancellation: TaskCancellation? = nil
    ) -> Bool {
        guard isActive else { return false }
        let point = CGPoint(x: CGFloat(absX), y: CGFloat(absY))

        do {
            let original: CGPoint? = background ? currentCursorLocation() : nil
            switch type {
            case .single:
                try singleClick(at: point)
            case .double:
                try doubleClick(at: point)
            case .longPress:
                try longPress(at: point, durationMs: durationMs, cancellation: cancellation)
            }
            if let original { postMove(to: original) }
            return true
        } catch {
            return false
        }
    }

    /// Click-drag from one absolute point to another. Used for swipe gestures
    /// (e.g. iOS App Switcher force-quit through iPhone Mirroring).
    @discardableResult
    func swipe(
        from startAbs: CGPoint, to endAbs: CGPoint,
        durationMs: Int = 300,
        steps: Int = 24,
        cancellation: TaskCancellation? = nil
    ) -> Bool {
        guard isActive else { return false }
        let steps = max(2, steps)
        let interval = TimeInterval(durationMs) / 1000.0 / TimeInterval(steps)
        do {
            try postEvent(type: .leftMouseDown, at: startAbs)
            for s in 1...steps {
                if Task.isCancelled || (cancellation?.isCancelled ?? false) { break }
                let t = CGFloat(s) / CGFloat(steps)
                let p = CGPoint(
                    x: startAbs.x + (endAbs.x - startAbs.x) * t,
                    y: startAbs.y + (endAbs.y - startAbs.y) * t
                )
                try postEvent(type: .leftMouseDragged, at: p)
                Thread.sleep(forTimeInterval: interval)
            }
            try postEvent(type: .leftMouseUp, at: endAbs)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Internals

    private func singleClick(at point: CGPoint) throws {
        try postEvent(type: .leftMouseDown, at: point)
        Thread.sleep(forTimeInterval: 0.05)
        try postEvent(type: .leftMouseUp, at: point)
    }

    private func doubleClick(at point: CGPoint) throws {
        // First click with clickState=1
        try postEvent(type: .leftMouseDown, at: point, clickState: 1)
        try postEvent(type: .leftMouseUp,   at: point, clickState: 1)
        Thread.sleep(forTimeInterval: 0.05)
        // Second click with clickState=2
        try postEvent(type: .leftMouseDown, at: point, clickState: 2)
        try postEvent(type: .leftMouseUp,   at: point, clickState: 2)
    }

    private func longPress(
        at point: CGPoint,
        durationMs: Int,
        cancellation: TaskCancellation?
    ) throws {
        try postEvent(type: .leftMouseDown, at: point)
        // Interruptible hold: poll cancellation in 20ms slices.
        let total = TimeInterval(max(0, durationMs)) / 1000.0
        let slice = TimeInterval(0.02)
        var waited: TimeInterval = 0
        while waited < total {
            if Task.isCancelled || (cancellation?.isCancelled ?? false) { break }
            let remaining = total - waited
            Thread.sleep(forTimeInterval: min(slice, remaining))
            waited += slice
        }
        try postEvent(type: .leftMouseUp, at: point)
    }

    private func postEvent(
        type: CGEventType,
        at point: CGPoint,
        clickState: Int64 = 0
    ) throws {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw CGEventError.creationFailed
        }
        if clickState != 0 {
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
        }
        event.post(tap: postTap)
    }

    private func postMove(to point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.post(tap: postTap)
    }

    /// Capture the current global cursor position via a synthetic CGEvent,
    /// mirroring Python's `CGEventCreate(None) → CGEventGetLocation`.
    private func currentCursorLocation() -> CGPoint {
        if let event = CGEvent(source: nil) {
            return event.location
        }
        // Fallback to AppKit.
        return NSEvent.mouseLocation
    }
}

enum CGEventError: Error { case creationFailed }

/// Lightweight cancellation handle so the engine can interrupt long presses
/// and swipes without depending on a Swift `Task`. Used by ClickExecutor.
final class TaskCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        _cancelled = true
    }
    func reset() {
        lock.lock(); defer { lock.unlock() }
        _cancelled = false
    }
}
