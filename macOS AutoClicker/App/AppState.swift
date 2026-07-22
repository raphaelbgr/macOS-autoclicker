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
import UniformTypeIdentifiers

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
    /// Action ids in most-recently-fired order (front = most recent). Drives
    /// the optional "Sort by activity" ordering in the timeline.
    @Published var activityOrder: [UUID] = []
    /// The action id that just fired, for a brief fade highlight; cleared ~1s later.
    @Published var justFiredID: UUID?
    /// Last fired click point in the same coordinate space as the captured
    /// frame (window-relative for window targets, absolute for full screen,
    /// region-relative for region). Drives the ripple overlay in LivePreviewView.
    /// Cleared ~1.2s after the most recent fire.
    @Published var lastFiredPoint: CGPoint?
    /// Label of the most recently fired action, shown under the live preview
    /// alongside the ripple. Tracks `lastFiredPoint`'s lifetime.
    @Published var lastFiredLabel: String = ""
    @Published var status: String = "Idle"

    // MARK: - Engine

    @Published var automationRunning: Bool = false
    @Published var logEntries: [LogEntry] = []

    private let engine = AutomationEngine()
    private var engineTask: Task<Void, Never>?
    /// Per-fire token used to race-guard `lastFiredPoint`'s clear timer.
    /// Each fire writes a fresh UUID; only the latest timer survives.
    private var lastFiredToken: UUID?

    // MARK: - Logger

    let logger = AppLogger()

    init() {
        UITestLaunchHooks.handleLaunchArguments()
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

    /// Prompt user to pick a project folder (timeline.json + screenshots/) OR
    /// a bare timeline JSON file (the Python app also saved standalone
    /// "<name> clicks.json" files) and import it as a new project.
    func importProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.title = "Select a project folder (timeline.json) or a timeline JSON file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let project: Project
            if url.hasDirectoryPath {
                project = try Project.importFrom(folder: url, as: url.lastPathComponent)
            } else {
                project = try Project.importFrom(timelineFile: url)
            }
            loadProjectList()
            selectProject(project.name)
            logger.info("Imported project \"\(project.name)\"")
        } catch {
            status = "Import failed: \(error.localizedDescription)"
            logger.error("Import failed: \(error.localizedDescription)")
        }
    }

    /// Export the selected project as a self-contained folder the user picks.
    func exportProject() {
        guard let name = selectedProjectName else { return }
        let panel = NSSavePanel()
        panel.title = "Export \(name)"
        panel.prompt = "Export"
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Project(name: name).exportTo(folder: url)
            logger.info("Exported project \"\(name)\" to \(url.path)")
            status = "Exported to \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            status = "Export failed: \(error.localizedDescription)"
            logger.error("Export failed: \(error.localizedDescription)")
        }
    }

    /// Tell the MainWindow to show the Add Action sheet.
    /// MainWindow observes this flag.
    @Published var presentingAddAction = false
    func presentAddAction() {
        presentingAddAction = true
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
            if timeline.actions.indices.contains(index) {
                let action = timeline.actions[index]
                let id = action.id
                activityOrder.removeAll { $0 == id }
                activityOrder.insert(id, at: 0)
                justFiredID = id
                // Publish the fired click point for the live-preview ripple.
                // action.x/y are already in the same coordinate space as the
                // captured frame (window-relative, absolute, or region-relative).
                lastFiredPoint = CGPoint(x: action.x, y: action.y)
                lastFiredLabel = action.label.isEmpty ? "Action #\(index + 1)" : action.label
                let token = UUID()
                lastFiredToken = token
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if self?.justFiredID == id { self?.justFiredID = nil }
                }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    // Only clear if no newer fire has replaced us.
                    if self?.lastFiredToken == token {
                        self?.lastFiredPoint = nil
                    }
                }
            }
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

/// Launch-argument hooks consumed by the XCUITest target. Outside the test
/// runner these arguments are never present, so this is a no-op in production.
enum UITestLaunchHooks {
    static func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        // -uitest-onboarding-test: used only by the onboarding UI test. Resets
        // persistence and leaves the onboarding flag UNSET so the overlay renders,
        // even when -uitest-skip-onboarding is also present. The onboarding test's
        // exact launch-argument set was tuned empirically for reliable window
        // creation under XCUITest.
        let isOnboardingTest = args.contains("-uitest-onboarding-test")
        if args.contains("-uitest-reset") || isOnboardingTest {
            wipePersistence()
        }
        // Apply AFTER the wipe so the flag survives a reset.
        if args.contains("-uitest-skip-onboarding") && !isOnboardingTest {
            UserDefaults.standard.set(true, forKey: "hasCompletedPermissionOnboarding")
        }
    }

    private static func wipePersistence() {
        // Remove only app-level keys, not the entire UserDefaults domain.
        // This preserves NSWindow frame/restoration keys that SwiftUI's
        // WindowGroup relies on for reliable window creation.
        let defaults = UserDefaults.standard
        let appKeys = [
            "hasCompletedPermissionOnboarding"
        ]
        for key in appKeys {
            defaults.removeObject(forKey: key)
        }
        let fm = FileManager.default
        if let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let root = base.appendingPathComponent("macOS-autoclicker", isDirectory: true)
            try? fm.removeItem(at: root)
        }
    }
}
