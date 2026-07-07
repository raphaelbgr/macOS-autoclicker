//
//  TargetSpec.swift
//  macOS AutoClicker
//
//  What an automation project captures and clicks into.
//
//  This is THE generalization over the old Python app, which only ever
//  targeted iPhone Mirroring. Four variants cover every case:
//
//  - .iphoneMirroring:   legacy preset; unlocks Home/AppSwitcher/Spotlight
//  - .window:            any open window (by owner + windowID)
//  - .region:            a screen rectangle in global display coordinates
//  - .fullScreen:        an entire display (multi-monitor aware)
//

import Foundation
import CoreGraphics

/// Identifies what a project targets. Codable so it persists in settings.json.
indirect enum TargetSpec: Codable, Hashable, Sendable {
    /// The iPhone Mirroring preset. Backed by `.window` lookup but carries
    /// the semantic flag that unlocks iOS-specific actions.
    case iphoneMirroring

    /// A specific window, identified by its owner process name and the
    /// CGWindowID assigned by the window server. The windowID is stable
    /// for the lifetime of the window but not across relaunches, so the
    /// owner name is the primary key at runtime.
    case window(owner: String, windowID: CGWindowID)

    /// A rectangular region in global display coordinates.
    case region(CGRect)

    /// An entire display, by CGDirectDisplayID.
    case fullScreen(CGDirectDisplayID)

    // MARK: - Codable (human-readable JSON)
    //
    // We deliberately avoid retroactively conforming CGRect to Codable —
    // the SDK already conforms it (encoding as nested arrays
    // [[x,y],[w,h]]) and a retroactive conformance would be shadowed and
    // produce a "pie, y, width, height" dict that never actually runs.
    // Instead, we route the region through a private wrapper that yields
    // the readable shape we want in settings.json.
    private struct RectDTO: Codable {
        let x: Double; let y: Double
        let width: Double; let height: Double
        init(_ r: CGRect) { x = r.origin.x; y = r.origin.y; width = r.width; height = r.height }
        var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, owner, windowID, rect, displayID
    }
    private enum Kind: String, Codable {
        case iphoneMirroring = "iphone_mirroring"
        case window, region, fullScreen = "full_screen"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .iphoneMirroring:
            self = .iphoneMirroring
        case .window:
            self = .window(
                owner: try c.decode(String.self, forKey: .owner),
                windowID: CGWindowID(try c.decode(Int.self, forKey: .windowID))
            )
        case .region:
            let dto = try c.decode(RectDTO.self, forKey: .rect)
            self = .region(dto.rect)
        case .fullScreen:
            self = .fullScreen(CGDirectDisplayID(try c.decode(Int.self, forKey: .displayID)))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .iphoneMirroring:
            try c.encode(Kind.iphoneMirroring, forKey: .kind)
        case .window(let owner, let wid):
            try c.encode(Kind.window, forKey: .kind)
            try c.encode(owner, forKey: .owner)
            try c.encode(Int(wid), forKey: .windowID)
        case .region(let rect):
            try c.encode(Kind.region, forKey: .kind)
            try c.encode(RectDTO(rect), forKey: .rect)
        case .fullScreen(let did):
            try c.encode(Kind.fullScreen, forKey: .kind)
            try c.encode(Int(did), forKey: .displayID)
        }
    }

    /// Display name for the UI.
    var displayName: String {
        switch self {
        case .iphoneMirroring:           return "iPhone Mirroring"
        case .window(let owner, _):      return owner
        case .region:                    return "Screen Region"
        case .fullScreen:                return "Full Screen"
        }
    }

    /// Whether this target enables the iOS app-lifecycle actions
    /// (Home, App Switcher, Spotlight, Open/Close App).
    var enablesIOSActions: Bool {
        if case .iphoneMirroring = self { return true }
        return false
    }
}
