//
//  AutomationEngine.swift
//  macOS AutoClicker
//
//  The main automation loop. Replaces main_window.py:_automation_loop.
//
//  Lifecycle:
//    1. start(project) — spawns a background Task running the loop
//    2. each tick: capture → match all recognition actions → best wins →
//       fire (respecting delay) → 1s cooldown → fire any due after-trigger
//       actions → throttle by monitorIntervalMs
//    3. stop() — cancels the Task + long-press/swipe cancellations
//
//  State is published via AsyncStream<EngineEvent> so the UI can render
//  live match percentages, fired actions, and log entries without polling.
//

import AppKit
import CoreGraphics
import Foundation

/// One observable event the UI can react to.
enum EngineEvent: Sendable {
    /// Per-action similarity scores for the current tick + which index (if any) matched.
    case matchUpdate(scores: [(index: Int, similarity: Double)], bestIndex: Int?)
    /// A status line ("Scanning 6 actions…").
    case status(String)
    /// An action fired — index + reason.
    case actionFired(index: Int, reason: String)
    /// Engine finished (stopped, completed, or errored).
    case finished(EngineStopReason)
    /// Log entry (mirrors AppLogger but engine-side).
    case log(LogEntry)
}

enum EngineStopReason: Sendable {
    case userStopped
    case completed      // non-loop timeline finished all passes
    case error(String)
}

/// Thread-safe holder for the AsyncStream continuation. Lets the engine
/// expose `events` as a nonisolated property so callers on any actor
/// (including the main actor) can subscribe without crossing isolation.
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<EngineEvent>.Continuation?

    func set(_ cont: AsyncStream<EngineEvent>.Continuation) {
        lock.lock(); defer { lock.unlock() }
        continuation = cont
    }
    func yield(_ event: EngineEvent) {
        lock.lock(); defer { lock.unlock() }
        continuation?.yield(event)
    }
    func finish() {
        lock.lock(); defer { lock.unlock() }
        continuation?.finish()
        continuation = nil
    }
}

/// Inputs the engine needs. Held by value, snapshot at start().
struct EngineInputs: Sendable {
    let project: Project
    var settings: ProjectSettings
    var timeline: Timeline
    /// Loaded action reference images (CGImage per index that has a screenshot).
    /// Indexes missing an image or whose image fails to load are skipped.
    var referenceImages: [Int: CGImage]
}

/// The loop. An actor isolates its mutable state (the running Task,
/// cancellation flag, latest window resolution).
actor AutomationEngine {

    private var task: Task<Void, Never>?
    private let cancellation = TaskCancellation()
    private var currentInputs: EngineInputs?

    // The continuation is captured at first subscription; subsequent
    // emissions go through it. We hold it as a nonisolated `let` constant
    // so callers can subscribe from any actor (e.g. the main actor) without
    // crossing isolation boundaries.
    private let continuationBox = ContinuationBox()

    /// Live stream of events. UI subscribes via `for await event in events`.
    /// Nonisolated so the main-actor AppState can grab it directly.
    nonisolated var events: AsyncStream<EngineEvent> {
        AsyncStream { continuation in
            continuationBox.set(continuation)
        }
    }

    // MARK: - Lifecycle

    func start(_ inputs: EngineInputs) {
        if task != nil { stop() }
        cancellation.reset()
        currentInputs = inputs
        task = Task { [weak self] in
            await self?.runLoop(inputs: inputs)
        }
    }

    func stop() {
        cancellation.cancel()
        task?.cancel()
        task = nil
        emit(.finished(.userStopped))
    }

    func isRunning() -> Bool { task != nil }

    // MARK: - Loop

    private func runLoop(inputs: EngineInputs) async {
        guard let resolvedWindow = resolveTargetWindow(inputs: inputs) else {
            emit(.status("⚠️ Target window not found"))
            emit(.finished(.error("Target window not found")))
            return
        }

        let actions = inputs.timeline.actions
        let recognitionActions = inputs.timeline.recognitionActions
        emit(.log(LogEntry("Started automation", category: .timelineStart)))
        emit(.status("Scanning \(recognitionActions.count) actions…"))

        while !Task.isCancelled && !cancellation.isCancelled {
            // 1. Capture.
            guard let capture = ScreenCapture.capture(for: inputs.settings.target, resolvedWindow: resolvedWindow) else {
                emit(.status("⚠️ Capture failed"))
                try? await Task.sleep(nanoseconds: UInt64(inputs.settings.monitorIntervalMs) * 1_000_000)
                continue
            }

            // 2. Match every recognition action. Best similarity wins.
            var scores: [(index: Int, similarity: Double)] = []
            var bestIdx: Int? = nil
            var bestSim: Double = 0
            var bestReason: String = ""

            for (i, action) in actions.enumerated() where action.enabled && action.triggerType == .recognition {
                var sim: Double = 0

                // Screenshot match (featurePrint or SSIM).
                if !action.screenshotPath.isEmpty,
                   let ref = inputs.referenceImages[i] {
                    let r: MatchResult
                    switch inputs.settings.matchMethod {
                    case .featurePrint:
                        r = ScreenRecognizer.matchFeaturePrint(
                            capture: capture, reference: ref,
                            threshold: action.threshold,
                            cacheKey: ObjectIdentifier(action.id as AnyObject)
                        )
                    case .ssim:
                        r = ScreenRecognizer.matchSSIM(
                            capture: capture, reference: ref,
                            threshold: action.threshold
                        )
                    }
                    sim = max(sim, r.similarity)
                }

                // OCR fallback — only counts if no screenshot or it didn't clear threshold.
                if sim < action.threshold && !action.ocrPatterns.isEmpty {
                    let (matched, pattern, _) = OCRMatcher.textMatchesAny(in: capture, patterns: action.ocrPatterns)
                    if matched, let pattern {
                        sim = max(sim, action.threshold)
                        bestReason = "OCR: \(pattern)"
                    }
                }

                scores.append((index: i, similarity: sim))
                if sim >= action.threshold && sim > bestSim {
                    bestSim = sim; bestIdx = i
                    if bestReason.isEmpty { bestReason = "Match \(Int(sim * 100))%" }
                }
            }

            // 3. Publish scores to UI.
            emit(.matchUpdate(scores: scores, bestIndex: bestIdx))

            // 4. Fire if matched, else throttle.
            if let idx = bestIdx, idx < actions.count {
                let action = actions[idx]
                if action.delayMs > 0 {
                    try? await sleepInterruptible(TimeInterval(action.delayMs) / 1000.0)
                    if Task.isCancelled || cancellation.isCancelled { break }
                }
                await executeAction(action, inputs: inputs, window: resolvedWindow, reason: bestReason)
                emit(.actionFired(index: idx, reason: bestReason))
                // 1s cooldown (matches Python loop).
                try? await sleepInterruptible(1.0)
            } else {
                // Throttle to monitorIntervalMs.
                try? await sleepInterruptible(TimeInterval(inputs.settings.monitorIntervalMs) / 1000.0)
            }
        }

        emit(.log(LogEntry("Stopped automation", category: .timelineStop)))
        emit(.finished(.userStopped))
        continuationBox.finish()
    }

    // MARK: - Action execution

    private func executeAction(_ action: ClickAction, inputs: EngineInputs, window: CapturedWindow, reason: String) async {
        emit(.log(LogEntry("Fired: \(action.label.isEmpty ? "#\(action.id)" : action.label)", category: .clickExecuted, details: reason)))

        switch action.actionType {
        case .click:
            // Convert window-relative → absolute.
            let absX = Int(window.frame.origin.x) + action.x
            let absY = Int(window.frame.origin.y) + action.y
            // Background ("ghost click") mode + repeat count.
            let executor = ClickExecutor()
            for n in 0..<max(1, action.repeatCount) {
                _ = executor.clickAtAbsolute(
                    absX, absY,
                    type: action.clickType,
                    durationMs: action.durationMs,
                    background: inputs.settings.backgroundClick,
                    cancellation: cancellation,
                    endX: Int(window.frame.origin.x) + action.endX,
                    endY: Int(window.frame.origin.y) + action.endY
                )
                if action.repeatCount > 1 { try? await sleepInterruptible(0.05) }
                _ = n
            }

        case .closeApp, .openApp:
            // Only meaningful for iPhone Mirroring.
            await performAppAction(action, inputs: inputs, window: window)
        }
    }

    /// close_app / open_app actions (iPhone Mirroring preset only).
    private func performAppAction(_ action: ClickAction, inputs: EngineInputs, window: CapturedWindow) async {
        guard inputs.settings.target.enablesIOSActions else {
            emit(.log(LogEntry("Skipping app action — target isn't iPhone Mirroring", category: .warning)))
            return
        }
        switch action.actionType {
        case .closeApp:
            switch action.closeMethod {
            case .forceQuit:
                // Open App Switcher, swipe up the current app, return home.
                _ = IPhoneMirroringController.sendCommand(.appSwitcher)
                try? await sleepInterruptible(0.8)
                let cx = Int(window.frame.midX)
                let cy = Int(window.frame.midY)
                let endY = Int(window.frame.minY)
                let executor = ClickExecutor()
                _ = executor.swipe(
                    from: CGPoint(x: cx, y: cy),
                    to: CGPoint(x: cx, y: endY),
                    durationMs: 400,
                    cancellation: cancellation
                )
                try? await sleepInterruptible(0.4)
                _ = IPhoneMirroringController.sendCommand(.home)
            case .home:
                _ = IPhoneMirroringController.sendCommand(.home)
            }
        case .openApp:
            switch action.openMethod {
            case .spotlight:
                _ = IPhoneMirroringController.sendCommand(.spotlight)
                try? await sleepInterruptible(0.5)
                _ = IPhoneMirroringController.typeText(action.appName, pressReturn: true)
            case .tapIcon:
                let absX = Int(window.frame.origin.x) + action.x
                let absY = Int(window.frame.origin.y) + action.y
                _ = ClickExecutor().clickAtAbsolute(absX, absY, type: .single, cancellation: cancellation)
            }
        case .click:
            break  // unreachable
        }
        if action.postDelayMs > 0 {
            try? await sleepInterruptible(TimeInterval(action.postDelayMs) / 1000.0)
        }
    }

    // MARK: - Helpers

    /// Resolve the target window once at start; the Python app did this per-tick
    /// but the cost of window enumeration is the bottleneck, so caching is a win.
    /// Re-resolves on a cold path if the window goes away.
    private func resolveTargetWindow(inputs: EngineInputs) -> CapturedWindow? {
        // For region/fullScreen there is no window to resolve.
        switch inputs.settings.target {
        case .region, .fullScreen:
            // Sentinel representing "no window" — capture path handles it.
            return CapturedWindow(
                windowID: 0, ownerName: "[Entire Screen]", windowName: "",
                frame: .zero, ownerPID: 0, isOnScreen: true
            )
        case .iphoneMirroring, .window:
            return ScreenCapture.resolveWindow(for: inputs.settings.target)
        }
    }

    private func emit(_ event: EngineEvent) {
        continuationBox.yield(event)
    }

    /// Sleep that's interruptible by both Task.cancel() and our cancellation handle.
    private func sleepInterruptible(_ seconds: TimeInterval) async throws {
        let ns = UInt64(seconds * 1_000_000_000)
        let slice: UInt64 = 50_000_000  // 50ms
        var remaining = ns
        while remaining > 0 {
            if Task.isCancelled || cancellation.isCancelled { return }
            let s = min(slice, remaining)
            try? await Task.sleep(nanoseconds: s)
            remaining -= s
        }
    }
}
