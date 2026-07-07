//
//  Timeline.swift
//  macOS AutoClicker
//
//  A sequence of click actions. Ported from src/timeline.py Timeline.
//  Same on-disk JSON schema.
//

import Foundation

/// Ordered list of ClickActions plus loop settings. Codable; the on-disk
/// layout matches the Python app's timeline.json exactly:
/// `{"name", "loop", "loop_count", "actions": [...]}`.
struct Timeline: Codable, Hashable, Sendable {
    var name: String = "Untitled"
    var actions: [ClickAction] = []
    var loop: Bool = false
    /// 0 = infinite (only meaningful when `loop == true`); otherwise the
    /// total number of passes through the action list.
    var loopCount: Int = 1

    private enum CodingKeys: String, CodingKey {
        case name, actions, loop
        case loopCount = "loop_count"
    }

    init() {}
    init(name: String, actions: [ClickAction] = [], loop: Bool = false, loopCount: Int = 1) {
        self.name = name; self.actions = actions
        self.loop = loop; self.loopCount = max(0, loopCount)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name     = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        actions  = try c.decodeIfPresent([ClickAction].self, forKey: .actions) ?? []
        loop     = try c.decodeIfPresent(Bool.self, forKey: .loop) ?? false
        loopCount = max(0, try c.decodeIfPresent(Int.self, forKey: .loopCount) ?? 1)
    }

    // MARK: - Mutations (mirrors the Python API surface)

    mutating func add(_ action: ClickAction) {
        actions.append(action)
    }

    @discardableResult
    mutating func remove(at index: Int) -> ClickAction? {
        guard actions.indices.contains(index) else { return nil }
        return actions.remove(at: index)
    }

    mutating func update(at index: Int, with action: ClickAction) {
        guard actions.indices.contains(index) else { return }
        actions[index] = action
    }

    mutating func swap(_ a: Int, _ b: Int) {
        guard actions.indices.contains(a), actions.indices.contains(b) else { return }
        actions.swapAt(a, b)
    }

    mutating func clear() {
        actions.removeAll()
    }

    /// Only actions that contribute to recognition matching this tick.
    /// (`after_trigger` actions fire on a different code path.)
    var recognitionActions: [ClickAction] {
        actions.filter { $0.triggerType == .recognition }
    }

    var totalDurationMs: Int {
        actions.reduce(0) { $0 + $1.delayMs + $1.durationMs }
    }
}
