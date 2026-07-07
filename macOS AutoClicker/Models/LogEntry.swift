//
//  LogEntry.swift
//  macOS AutoClicker
//
//  In-memory log with observer pattern. Ported from src/logger.py.
//  Categories match the Python app's LogCategory enum exactly so log
//  colors and semantics stay consistent.
//

import Foundation
import SwiftUI

/// Logical category of a log line. Maps to the Python `LogCategory` enum.
enum LogCategory: String, Codable, Sendable {
    case screenMatch     = "MATCH"
    case screenMismatch  = "MISMATCH"
    case clickExecuted   = "CLICK"
    case timelineStart   = "TIMELINE_START"
    case timelineStop    = "TIMELINE_STOP"
    case stateChange     = "STATE"
    case error           = "ERROR"
    case warning         = "WARNING"
    case info            = "INFO"

    /// Color used in the activity log view.
    var color: Color {
        switch self {
        case .screenMatch:     return DesignTokens.Log.match
        case .screenMismatch:  return DesignTokens.Log.mismatch
        case .clickExecuted:   return DesignTokens.Log.click
        case .timelineStart:   return DesignTokens.Log.start
        case .timelineStop:    return DesignTokens.Log.stop
        case .stateChange:     return DesignTokens.Log.state
        case .error:           return DesignTokens.Log.error
        case .warning:         return DesignTokens.Log.warning
        case .info:            return DesignTokens.Log.info
        }
    }
}

struct LogEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    let timestamp: Date
    let category: LogCategory
    let message: String
    var details: String? = nil

    init(_ message: String, category: LogCategory, details: String? = nil, at date: Date = Date()) {
        self.timestamp = date
        self.category = category
        self.message = message
        self.details = details
    }

    /// Formatted exactly like the Python app: `[HH:MM:SS.mmm] [CATEGORY    ] message | details`.
    var formatted: String {
        let ts = timestamp.formatted(.dateTime.hour().minute().second())
        let ms = Int(timestamp.timeIntervalSince1970 * 1000) % 1000
        let catPad = category.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
        var line = "[\(ts).\(String(format: "%03d", ms))] [\(catPad)] \(message)"
        if let details { line += " | \(details)" }
        return line
    }
}

/// Observable ring-buffer of log entries, with listener notifications.
/// MainActor because views observe it.
@MainActor
final class AppLogger: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []
    private let maxEntries: Int
    private let dateFormatter: DateFormatter
    private var fileURL: URL?

    init(maxEntries: Int = 5000) {
        self.maxEntries = maxEntries
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
    }

    /// Enables file mirroring under the given directory.
    func startFileLogging(in dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "autoclicker_\(dateFormatter.string(from: Date())).log"
        fileURL = dir.appendingPathComponent(filename)
    }

    func log(_ message: String, category: LogCategory, details: String? = nil) {
        let entry = LogEntry(message, category: category, details: details)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        if let fileURL {
            FileLogCoordinator.shared.append(entry.formatted, to: fileURL)
        }
    }

    // Convenience methods mirroring the Python AppLogger API.
    func info(_ msg: String, details: String? = nil)     { log(msg, category: .info, details: details) }
    func warning(_ msg: String, details: String? = nil)  { log(msg, category: .warning, details: details) }
    func error(_ msg: String, details: String? = nil)    { log(msg, category: .error, details: details) }
    func match(_ msg: String, details: String? = nil)    { log(msg, category: .screenMatch, details: details) }
    func mismatch(_ msg: String, details: String? = nil) { log(msg, category: .screenMismatch, details: details) }
    func click(_ msg: String, details: String? = nil)    { log(msg, category: .clickExecuted, details: details) }

    func clear() { entries.removeAll() }

    func export(to url: URL) throws {
        let text = entries.map(\.formatted).joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Serializes file appends off the main thread. We never block UI on disk.
private final class FileLogCoordinator: @unchecked Sendable {
    static let shared = FileLogCoordinator()
    private let queue = DispatchQueue(label: "mac-autoclicker.filelog")

    func append(_ line: String, to url: URL) {
        queue.async {
            let data = (line + "\n").data(using: .utf8) ?? Data()
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
