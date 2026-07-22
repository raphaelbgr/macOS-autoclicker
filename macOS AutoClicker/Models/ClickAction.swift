//
//  ClickAction.swift
//  macOS AutoClicker
//
//  A single action triggered by screen matching. Ported from
//  src/timeline.py ClickAction (Python). Same on-disk schema so
//  existing timeline.json files import without modification.
//

import Foundation

/// Type of synthetic click to perform.
enum ClickType: String, Codable, CaseIterable, Sendable {
    case single
    case double
    case longPress = "long_press"
    case rightClick = "right_click"
    case middleClick = "middle_click"
    case tripleClick = "triple_click"
    case scrollUp = "scroll_up"
    case scrollDown = "scroll_down"
    case drag

    /// Python schema uses "long_press" — alias kept for compatibility.
    static func from(_ raw: String) -> ClickType {
        Self(rawValue: raw) ?? .single
    }
}

/// Whether the action is a plain click or an app-lifecycle action
/// (open/close app — only meaningful for the iPhone Mirroring preset).
enum ActionType: String, Codable, Sendable {
    case click
    case closeApp = "close_app"
    case openApp  = "open_app"
}

/// How a close_app action closes the target app.
enum CloseMethod: String, Codable, Sendable {
    case forceQuit = "force_quit"  // App Switcher swipe-up
    case home
}

/// How an open_app action launches the target.
enum OpenMethod: String, Codable, Sendable {
    case spotlight  // type name in Spotlight, press return
    case tapIcon    // tap (x,y) icon
}

/// When the action should fire.
enum TriggerType: String, Codable, Sendable {
    case recognition   // screenshot/text match
    case afterTrigger  = "after_trigger"  // delay after another action
}

/// A single click/app action and its match conditions.
///
/// Mirrors the Python `ClickAction` dataclass field-for-field. The Codable
/// conformance is custom so the on-disk JSON exactly matches the old app:
/// - `screenshot_path` / `match_texts` only emitted when non-empty
/// - app-lifecycle fields only emitted when `actionType != .click`
/// - trigger fields only emitted when `triggerType != .recognition`
/// - legacy `timestamp_ms` accepted on decode (mapped to `delay_ms`)
struct ClickAction: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()

    // MARK: - Core
    var delayMs: Int = 0
    var x: Int = 0
    var y: Int = 0
    // Drag end point (only meaningful when clickType == .drag).
    var endX: Int = 0
    var endY: Int = 0
    var clickType: ClickType = .single
    var durationMs: Int = 100
    var label: String = ""
    var threshold: Double = 0.85
    var enabled: Bool = true
    var repeatCount: Int = 1

    // MARK: - Match sources (each optional — empty = no contribution)
    var screenshotPath: String = ""
    var matchTexts: String = ""

    // MARK: - App lifecycle (only relevant when actionType != .click)
    var actionType: ActionType = .click
    var closeMethod: CloseMethod = .forceQuit
    var openMethod: OpenMethod  = .spotlight
    var appName: String = ""
    var postDelayMs: Int = 0

    // MARK: - Trigger
    var triggerType: TriggerType = .recognition
    var afterIndex: Int = 1  // 1-based; only used when triggerType == .afterTrigger

    // MARK: - Codable (matches Python schema exactly)

    private enum CodingKeys: String, CodingKey {
        case delayMs         = "delay_ms"
        case timestampMs     = "timestamp_ms"  // legacy
        case x, y
        case endX            = "end_x"
        case endY            = "end_y"
        case clickType       = "click_type"
        case durationMs      = "duration_ms"
        case label
        case screenshotPath  = "screenshot_path"
        case threshold
        case matchTexts      = "match_texts"
        case enabled
        case repeatCount     = "repeat_count"
        case actionType      = "action_type"
        case closeMethod     = "close_method"
        case openMethod      = "open_method"
        case appName         = "app_name"
        case postDelayMs     = "post_delay_ms"
        case triggerType     = "trigger_type"
        case afterIndex      = "after_index"
        // id never serialized
    }

    init() {}

    init(
        delayMs: Int = 0,
        x: Int = 0,
        y: Int = 0,
        endX: Int = 0,
        endY: Int = 0,
        clickType: ClickType = .single,
        durationMs: Int = 100,
        label: String = "",
        threshold: Double = 0.85,
        enabled: Bool = true,
        repeatCount: Int = 1,
        screenshotPath: String = "",
        matchTexts: String = "",
        actionType: ActionType = .click,
        closeMethod: CloseMethod = .forceQuit,
        openMethod: OpenMethod = .spotlight,
        appName: String = "",
        postDelayMs: Int = 0,
        triggerType: TriggerType = .recognition,
        afterIndex: Int = 1
    ) {
        self.delayMs = delayMs
        self.x = x; self.y = y
        self.endX = endX; self.endY = endY
        self.clickType = clickType
        self.durationMs = durationMs
        self.label = label
        self.threshold = threshold
        self.enabled = enabled
        self.repeatCount = repeatCount
        self.screenshotPath = screenshotPath
        self.matchTexts = matchTexts
        self.actionType = actionType
        self.closeMethod = closeMethod
        self.openMethod = openMethod
        self.appName = appName
        self.postDelayMs = postDelayMs
        self.triggerType = triggerType
        self.afterIndex = afterIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy support: old files used timestamp_ms instead of delay_ms.
        if let legacy = try c.decodeIfPresent(Int.self, forKey: .timestampMs) {
            delayMs = legacy
        } else {
            delayMs = try c.decodeIfPresent(Int.self, forKey: .delayMs) ?? 0
        }
        x = try c.decodeIfPresent(Int.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Int.self, forKey: .y) ?? 0
        endX = try c.decodeIfPresent(Int.self, forKey: .endX) ?? 0
        endY = try c.decodeIfPresent(Int.self, forKey: .endY) ?? 0
        clickType = try c.decodeIfPresent(ClickType.self, forKey: .clickType) ?? .single
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs) ?? 100
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        screenshotPath = try c.decodeIfPresent(String.self, forKey: .screenshotPath) ?? ""
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.85
        matchTexts = try c.decodeIfPresent(String.self, forKey: .matchTexts) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        repeatCount = try c.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1
        actionType = try c.decodeIfPresent(ActionType.self, forKey: .actionType) ?? .click
        closeMethod = try c.decodeIfPresent(CloseMethod.self, forKey: .closeMethod) ?? .forceQuit
        openMethod = try c.decodeIfPresent(OpenMethod.self, forKey: .openMethod) ?? .spotlight
        appName = try c.decodeIfPresent(String.self, forKey: .appName) ?? ""
        postDelayMs = try c.decodeIfPresent(Int.self, forKey: .postDelayMs) ?? 0
        triggerType = try c.decodeIfPresent(TriggerType.self, forKey: .triggerType) ?? .recognition
        afterIndex = try c.decodeIfPresent(Int.self, forKey: .afterIndex) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(delayMs, forKey: .delayMs)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(clickType, forKey: .clickType)
        try c.encode(durationMs, forKey: .durationMs)
        try c.encode(label, forKey: .label)
        try c.encode(threshold, forKey: .threshold)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(repeatCount, forKey: .repeatCount)

        // Drag end point — only when this is a drag action.
        if clickType == .drag {
            try c.encode(endX, forKey: .endX)
            try c.encode(endY, forKey: .endY)
        }

        // Match-source fields — only when non-empty (matches Python behavior).
        if !screenshotPath.isEmpty { try c.encode(screenshotPath, forKey: .screenshotPath) }
        if !matchTexts.isEmpty     { try c.encode(matchTexts,     forKey: .matchTexts) }

        // App-lifecycle fields — only when this is a lifecycle action.
        if actionType != .click {
            try c.encode(actionType,  forKey: .actionType)
            try c.encode(closeMethod, forKey: .closeMethod)
            try c.encode(openMethod,  forKey: .openMethod)
            try c.encode(appName,     forKey: .appName)
            try c.encode(postDelayMs, forKey: .postDelayMs)
        }

        // Trigger fields — only when not the default.
        if triggerType != .recognition {
            try c.encode(triggerType, forKey: .triggerType)
            try c.encode(afterIndex,  forKey: .afterIndex)
        }
    }

    /// True when this action contributes to recognition-based firing.
    var isRecognitionTrigger: Bool {
        triggerType == .recognition && (!screenshotPath.isEmpty || !matchTexts.isEmpty)
    }

    /// Parsed OCR patterns (comma-separated, trimmed, non-empty).
    var ocrPatterns: [String] {
        matchTexts
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
