//
//  ProjectSettings.swift
//  macOS AutoClicker
//
//  Per-project runtime settings. Ported from src/project.py
//  ProjectSettings, with the key change that `targetApp` (a free-form
//  string in the Python app) becomes a typed `TargetSpec`.
//

import Foundation
import CoreGraphics

/// Per-project configuration. Persisted as `settings.json`.
struct ProjectSettings: Codable, Hashable, Sendable {
    /// Default SSIM/featurePrint threshold for newly-added actions.
    var threshold: Double = 0.85
    /// How often the automation loop captures + matches, in milliseconds.
    var monitorIntervalMs: Int = 500
    /// "Ghost click" mode: snap cursor to target, click, restore.
    var backgroundClick: Bool = false
    /// What this project targets. Replaces the old `target_app` string.
    var target: TargetSpec = .iphoneMirroring
    /// Visual match method. SSIM is the default — it's the pixel-exact algorithm
    /// the Python app used (scikit-image structural_similarity), so imported
    /// projects and their 0.85 thresholds behave the same. featurePrint (Vision
    /// semantic embedding) is the optional, shift-tolerant alternative.
    var matchMethod: MatchMethod = .ssim

    /// Compatibility bridge: the old Python app wrote `target_app` as a
    /// composite `"windowID::owner::windowName"` string. We translate it
    /// into a `TargetSpec.window(...)` on decode so existing projects
    /// import cleanly.
    private enum CodingKeys: String, CodingKey {
        case threshold
        case monitorIntervalMs = "monitor_interval_ms"
        case backgroundClick   = "background_click"
        case targetApp         = "target_app"  // legacy
        case target
        case matchMethod       = "match_method"
    }

    init() {}
    init(
        threshold: Double = 0.85,
        monitorIntervalMs: Int = 500,
        backgroundClick: Bool = false,
        target: TargetSpec = .iphoneMirroring,
        matchMethod: MatchMethod = .ssim
    ) {
        self.threshold = threshold
        self.monitorIntervalMs = monitorIntervalMs
        self.backgroundClick = backgroundClick
        self.target = target
        self.matchMethod = matchMethod
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.85
        monitorIntervalMs = try c.decodeIfPresent(Int.self, forKey: .monitorIntervalMs) ?? 500
        backgroundClick = try c.decodeIfPresent(Bool.self, forKey: .backgroundClick) ?? false
        matchMethod = try c.decodeIfPresent(MatchMethod.self, forKey: .matchMethod) ?? .ssim

        if let typed = try c.decodeIfPresent(TargetSpec.self, forKey: .target) {
            target = typed
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .targetApp) {
            target = Self.decodeLegacyTargetApp(legacy)
        } else {
            target = .iphoneMirroring
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(threshold, forKey: .threshold)
        try c.encode(monitorIntervalMs, forKey: .monitorIntervalMs)
        try c.encode(backgroundClick, forKey: .backgroundClick)
        try c.encode(matchMethod, forKey: .matchMethod)
        try c.encode(target, forKey: .target)
        // We no longer write the legacy `target_app` string on save.
    }

    /// Parse a legacy Python `target_app` value into a typed spec.
    /// Format was `"windowID::ownerName::windowName"` or just `"ownerName"`.
    private static func decodeLegacyTargetApp(_ raw: String) -> TargetSpec {
        let parts = raw.split(separator: "::", maxSplits: 2).map(String.init)
        let owner = parts.count >= 2 ? parts[1] : raw
        let lowered = owner.lowercased()
        if lowered == "iphone mirroring" || lowered.contains("iphone") {
            return .iphoneMirroring
        }
        if let widStr = parts.first, let wid = CGWindowID(widStr) {
            return .window(owner: owner, windowID: wid)
        }
        return .window(owner: owner, windowID: 0)
    }
}

/// How the recognizer compares the current capture against references.
enum MatchMethod: String, Codable, Sendable {
    /// Apple Vision featurePrint — semantic, robust to minor UI shifts.
    case featurePrint = "feature_print"
    /// Accelerate SSIM — pixel-exact, matches the Python app's behavior.
    case ssim
}
