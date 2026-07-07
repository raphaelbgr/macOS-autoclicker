//
//  AppState.swift
//  macOS AutoClicker
//
//  Root observable state. Owns the active project, settings, timeline, and
//  the AutomationEngine. Views observe this and never touch the engine
//  directly.
//

import Foundation
import SwiftUI
import KeyboardShortcuts

@MainActor
final class AppState: ObservableObject {

    // MARK: - Project list

    @Published var projects: [Project] = []
    @Published var selectedProjectName: String?

    // MARK: - Active project state

    @Published var settings: ProjectSettings = .init()
    @Published var timeline: Timeline = .init()
    /// Live similarity scores: action index → 0...1.
    @Published var similarities: [Int: Double] = [:]
    /// Index that just fired (for UI highlight).
    @Published var lastFiredIndex: Int?
    @Published var status: String = "Idle"

    // MARK: - Engine

    @Published var automationRunning: Bool = false
    @Published var logEntries: [LogEntry] = []

    private let engine = AutomationEngine()
    private var engineTask: Task<Void, Never>?

    // MARK: - Logger

    let logger = AppLogger()

    init() {
        loadProjectList()
        if projects.isEmpty {
            // Seed a default project so the UI has something to show.
            let p = Project(name: "My First Project")
            try? p.ensureExists()
            try? p.saveTimeline(Timeline(name: "My First Project"))
            try? p.saveSettings(ProjectSettings())
            projects = [p]
        }
        if let first = projects.first {
            selectProject(first.name)
        }
        // Mirror logger entries into @Published for SwiftUI.
        // (We keep the AppLogger as the source of truth for file output.)
        logger.startFileLogging(in: logsDirectory())
    }

    // MARK: - Project selection / creation

    func loadProjectList() {
        projects = Project.listProjects().map(Project.init(name:))
    }

    func selectProject(_ name: String) {
        selectedProjectName = name
        let p = Project(name: name)
        settings = p.loadSettings()
        timeline = p.loadTimeline() ?? Timeline(name: name)
        similarities.removeAll()
        lastFiredIndex = nil
        status = "Idle"
    }

    func newProject() {
        var name = "Untitled"
        var n = 2
        while Project.listProjects().contains(name) {
            name = "Untitled \(n)"; n += 1
        }
        let p = Project(name: name)
        try? p.ensureExists()
        try? p.saveTimeline(Timeline(name: name))
        try? p.saveSettings(ProjectSettings())
        loadProjectList()
        selectProject(name)
        logger.info("Created project \"\(name)\"")
    }

    func deleteProject(_ name: String) {
        let p = Project(name: name)
        try? FileManager.default.removeItem(at: p.directory)
        loadProjectList()
        if selectedProjectName == name {
            selectedProjectName = projects.first?.name
            if let n = selectedProjectName { selectProject(n) }
        }
    }

    // MARK: - Timeline mutation (auto-saves)

    func addAction(_ action: ClickAction) {
        timeline.add(action)
        persist()
    }

    func updateAction(at index: Int, with action: ClickAction) {
        timeline.update(at: index, with: action)
        persist()
    }

    func removeAction(at index: Int) {
        _ = timeline.remove(at: index)
        similarities.removeValue(forKey: index)
        persist()
    }

    func moveAction(from source: Int, to dest: Int) {
        // SwiftUI List.onMove gives indices in the new ordering; just trust
        // the timeline ordering and re-save.
        persist()
    }

    func setSettings(_ newSettings: ProjectSettings) {
        settings = newSettings
        persistSettings()
    }

    private func persist() {
        guard let name = selectedProjectName else { return }
        let p = Project(name: name)
        try? p.saveTimeline(timeline)
    }

    private func persistSettings() {
        guard let name = selectedProjectName else { return }
        let p = Project(name: name)
        try? p.saveSettings(settings)
    }

    private func logsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("macOS-autoclicker", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Automation lifecycle

    func startAutomation() {
        guard let name = selectedProjectName else { return }
        guard !timeline.actions.isEmpty else {
            status = "Add at least one action first"
            return
        }
        let project = Project(name: name)
        let inputs = EngineInputs(
            project: project,
            settings: settings,
            timeline: timeline,
            referenceImages: loadReferenceImages(for: project)
        )
        automationRunning = true
        status = "Starting…"

        // Subscribe to engine events on the main actor.
        engineTask?.cancel()
        let stream = engine.events
        engineTask = Task { [weak self] in
            guard let self else { return }
            for await event in stream {
                await self.handle(event)
            }
        }
        // Spawns the engine loop.
        Task { await engine.start(inputs) }
    }

    func stopAutomation() {
        Task { await engine.stop() }
        automationRunning = false
        engineTask?.cancel()
        engineTask = nil
    }

    /// Handle an engine event on the main actor — mutate @Published state.
    private func handle(_ event: EngineEvent) async {
        switch event {
        case .matchUpdate(let scores, let best):
            similarities.removeAll(keepingCapacity: true)
            for s in scores { similarities[s.index] = s.similarity }
            if let best {
                status = "Matched action #\(best + 1) (\(Int((similarities[best] ?? 0) * 100))%)"
            }
        case .status(let s):
            status = s
        case .actionFired(let index, let reason):
            lastFiredIndex = index
            logger.click("Action #\(index + 1)", details: reason)
        case .finished(let reason):
            automationRunning = false
            switch reason {
            case .userStopped:  status = "Stopped"
            case .completed:    status = "Completed"
            case .error(let e): status = "Error: \(e)"
            }
        case .log(let entry):
            logger.log(entry.message, category: entry.category, details: entry.details)
        }
        // Mirror logger → @Published for SwiftUI.
        logEntries = logger.entries
    }

    /// Load every per-action reference screenshot into a [index: CGImage].
    private func loadReferenceImages(for project: Project) -> [Int: CGImage] {
        var out: [Int: CGImage] = [:]
        for (i, action) in timeline.actions.enumerated() {
            guard !action.screenshotPath.isEmpty,
                  let ns = project.loadActionScreenshot(pathOrName: action.screenshotPath),
                  let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            out[i] = cg
        }
        return out
    }
}
