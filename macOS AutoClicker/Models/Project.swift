//
//  Project.swift
//  macOS AutoClicker
//
//  On-disk project persistence. Ported from src/project.py.
//
//  Layout (under ~/Library/Application Support/macOS-autoclicker/):
//
//    projects/<name>/
//    ├── timeline.json
//    ├── settings.json
//    └── screenshots/
//        └── action_<index>_<unix_ms>.png
//
//  Note: the Python app kept a single `reference.png` at the project root.
//  The new design gives every action its own reference screenshot, so the
//  global reference.png is read on import only (best-effort) and not
//  written going forward.
//

import Foundation
import AppKit
import CoreGraphics

enum ProjectStore {
    /// Root directory for all project data.
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("macOS-autoclicker", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// A project on disk. Cheap value type — re-resolves paths from `name`.
struct Project: Identifiable, Hashable, Sendable {
    let id = UUID()
    var name: String

    init(name: String) { self.name = name }

    var directory: URL {
        ProjectStore.root.appendingPathComponent(name, isDirectory: true)
    }
    var timelinePath: URL  { directory.appendingPathComponent("timeline.json") }
    var settingsPath: URL  { directory.appendingPathComponent("settings.json") }
    var screenshotsDir: URL {
        let d = directory.appendingPathComponent("screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    var legacyReferencePath: URL { directory.appendingPathComponent("reference.png") }

    var hasTimeline: Bool  { FileManager.default.fileExists(atPath: timelinePath.path) }
    var hasSettings: Bool  { FileManager.default.fileExists(atPath: settingsPath.path) }

    // MARK: - Persistence

    func ensureExists() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = screenshotsDir  // creates on access
    }

    func saveTimeline(_ timeline: Timeline) throws {
        try ensureExists()
        let data = try JSONEncoder.pretty.encode(timeline)
        try data.write(to: timelinePath, options: .atomic)
    }

    func loadTimeline() -> Timeline? {
        guard hasTimeline,
              let data = try? Data(contentsOf: timelinePath),
              let timeline = try? JSONDecoder().decode(Timeline.self, from: data)
        else { return nil }
        return timeline
    }

    func saveSettings(_ settings: ProjectSettings) throws {
        try ensureExists()
        let data = try JSONEncoder.pretty.encode(settings)
        try data.write(to: settingsPath, options: .atomic)
    }

    func loadSettings() -> ProjectSettings {
        guard hasSettings,
              let data = try? Data(contentsOf: settingsPath),
              let s = try? JSONDecoder().decode(ProjectSettings.self, from: data)
        else { return ProjectSettings() }
        return s
    }

    // MARK: - Per-action screenshots

    /// Saves an NSImage for a specific action. Returns the relative path
    /// (stored in ClickAction.screenshotPath). Same naming convention as
    /// the Python app: `action_<index>_<unix_ms>.png`.
    @discardableResult
    func saveActionScreenshot(index: Int, image: NSImage) throws -> String {
        try ensureExists()
        let unique = Int(Date().timeIntervalSince1970 * 1000)
        let filename = "action_\(index)_\(unique).png"
        let url = screenshotsDir.appendingPathComponent(filename)
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: url, options: .atomic)
        }
        return filename  // store relative — resolved via this project's screenshotsDir
    }

    /// Loads an action screenshot. Accepts either an absolute path (legacy
    /// imports) or a relative filename within this project's screenshotsDir.
    func loadActionScreenshot(pathOrName: String) -> NSImage? {
        guard !pathOrName.isEmpty else { return nil }
        let url: URL
        if pathOrName.hasPrefix("/") {
            url = URL(fileURLWithPath: pathOrName)
        } else {
            url = screenshotsDir.appendingPathComponent(pathOrName)
        }
        return NSImage(contentsOf: url)
    }

    /// Absolute URL for a stored relative screenshot path.
    func screenshotURL(forRelative relative: String) -> URL {
        screenshotsDir.appendingPathComponent(relative)
    }

    // MARK: - Listing / import

    /// Lists all project names on disk.
    static func listProjects() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: ProjectStore.root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    /// Imports a project from an external folder (e.g. the old Python
    /// repo's `projects/default/`). Copies timeline.json + screenshots.
    /// Throws if the source has no timeline.json. Settings.json is
    /// translated through the legacy-target decode path on first load.
    @discardableResult
    static func importFrom(folder: URL, as name: String? = nil) throws -> Project {
        let projName = name ?? folder.lastPathComponent
        let project = Project(name: projName)
        try project.ensureExists()

        // timeline.json (required)
        let srcTimeline = folder.appendingPathComponent("timeline.json")
        guard FileManager.default.fileExists(atPath: srcTimeline.path) else {
            throw ProjectError.missingTimeline
        }
        try? FileManager.default.removeItem(at: project.timelinePath)
        try FileManager.default.copyItem(at: srcTimeline, to: project.timelinePath)

        // screenshots/
        let srcScreenshots = folder.appendingPathComponent("screenshots")
        if FileManager.default.fileExists(atPath: srcScreenshots.path) {
            let dst = project.screenshotsDir
            if let items = try? FileManager.default.contentsOfDirectory(
                at: srcScreenshots, includingPropertiesForKeys: nil) {
                for item in items {
                    let dstItem = dst.appendingPathComponent(item.lastPathComponent)
                    try? FileManager.default.copyItem(at: item, to: dstItem)
                }
            }
        }

        // settings.json (optional; legacy decode path applies on load)
        let srcSettings = folder.appendingPathComponent("settings.json")
        if FileManager.default.fileExists(atPath: srcSettings.path) {
            try? FileManager.default.copyItem(at: srcSettings, to: project.settingsPath)
        }

        // Legacy reference.png (optional)
        let srcRef = folder.appendingPathComponent("reference.png")
        if FileManager.default.fileExists(atPath: srcRef.path) {
            try? FileManager.default.copyItem(at: srcRef, to: project.legacyReferencePath)
        }

        return project
    }
}

enum ProjectError: LocalizedError {
    case missingTimeline
    var errorDescription: String? {
        switch self {
        case .missingTimeline: return "No timeline.json found in the selected folder."
        }
    }
}

// MARK: - Shared encoder

extension JSONEncoder {
    /// Two-space indented, sorted keys — matches the Python app's output.
    static let pretty: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
