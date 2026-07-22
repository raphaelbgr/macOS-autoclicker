//
//  MainWindow.swift
//  macOS AutoClicker
//
//  Root shell. Uses HSplitView (sidebar | detail) instead of
//  NavigationSplitView for reliable rendering across macOS 13+.
//

import SwiftUI

struct MainWindow: View {
    @ObservedObject var appState: AppState
    @State private var showOnboarding = false
    @State private var showAdd = false
    /// Project name pending deletion; non-nil presents the confirmation dialog.
    @State private var pendingDelete: String?

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 400)
            detail
                .frame(minWidth: 600, minHeight: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("mainWindow")
        // First-launch permission onboarding. Rendered as an in-tree overlay
        // (NOT a `.sheet`) because the sheet presentation path is unreliable
        // under XCUITest — the host window may not composite, leaving the
        // sheet (and its buttons) inaccessible. Embedding onboarding in the
        // window's own view tree guarantees XCUITest can see both the window
        // and the onboarding controls.
        .overlay {
            if showOnboarding {
                onboardingOverlay
            }
        }
        .onAppear {
            if !UserDefaults.standard.bool(forKey: "hasCompletedPermissionOnboarding") {
                showOnboarding = true
            }
            refreshPermissionGate()
        }
        // Re-check the live permission state every 2s. If either required
        // permission is missing, surface the onboarding dialog again — the app
        // can't capture or click without them. Suppressed under UI tests so the
        // deterministic launch-argument flow stays in control.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refreshPermissionGate()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.presentAddAction()
                } label: {
                    Label("Add Action", systemImage: "plus.circle")
                }
                .disabled(appState.selectedProjectName == nil)
                .accessibilityIdentifier("addActionButton")
                .help("Open the action editor to add a new click to the current project")
            }
        }
    }

    /// True when launched by the XCUITest suite. The permission gate is
    /// suppressed here so tests drive onboarding purely via launch arguments.
    private var isUITest: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uitest") }
    }

    /// Query the live permission state off the main thread; if either required
    /// permission is missing, show the onboarding dialog. Never hides it (the
    /// user dismisses via Done/Skip once granted) and never runs under UI tests.
    private func refreshPermissionGate() {
        guard !isUITest else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = ScreenCapture.hasScreenRecordingPermission
                && ClickExecutor.hasAccessibilityPermission
            DispatchQueue.main.async {
                if !granted { showOnboarding = true }
            }
        }
    }

    // MARK: - Onboarding overlay

    /// Dimming layer + onboarding card, layered over the main HSplitView.
    /// Part of the window's own view tree (not a sheet) so it renders
    /// deterministically under XCUITest.
    @ViewBuilder
    private var onboardingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .help("Dimmed backdrop while permission setup is required — grant both permissions to dismiss")
            PermissionOnboardingSheet(appState: appState, isPresented: $showOnboarding)
                .frame(maxWidth: 480)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Projects")
                    .font(.headline)
                    .help("Your saved automation projects — each holds its own timeline of actions")
                Spacer()
                Button {
                    appState.newProject()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Create a new, empty project to start building a timeline")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.projects) { project in
                        sidebarRow(project)
                    }
                    if appState.projects.isEmpty {
                        Text("No projects yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .help("Click the + above to create your first project")
                    }
                }
                .padding(.vertical, 4)
            }
            Spacer()
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func sidebarRow(_ project: Project) -> some View {
        let isSelected = appState.selectedProjectName == project.name
        Button {
            appState.selectProject(project.name)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                Text(project.name)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .accessibilityIdentifier("sidebarProjectRow")
        .help("Open this project in the detail view — right-click for export/delete")
        .contextMenu {
            Button {
                appState.selectProject(project.name)
                appState.exportProject()
            } label: {
                Label("Export Project…", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) {
                pendingDelete = project.name
            } label: {
                Label("Delete Project…", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete ?? "")”?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                if let name = pendingDelete {
                    appState.deleteProject(name)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This permanently removes the project, its actions, and its screenshots from this Mac. Export it first if you want a backup.")
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let name = appState.selectedProjectName {
            VStack(spacing: 0) {
                headerStrip(name: name)
                Divider()
                controlBar
                Divider()
                bodySplit
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $appState.presentingAddAction) {
                ActionEditorSheet(appState: appState, isPresented: $appState.presentingAddAction, editIndex: nil)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No project selected")
                    .font(.title3)
                Text("Create a project from the sidebar to get started.")
                    .foregroundStyle(.secondary)
                Button("New Project") { appState.newProject() }
                    .buttonStyle(.borderedProminent)
                    .help("Create your first project to start adding actions")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func headerStrip(name: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.title2.bold())
                        .accessibilityIdentifier("headerProjectTitle")
                        .help("The currently open project — all actions below belong to it")
                    TargetPickerView(appState: appState)
                }
                Spacer()
                statusPill
                    .padding(.top, 6)
                    .help("Live run state of the automation engine for this project")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button {
                if appState.automationRunning {
                    appState.stopAutomation()
                } else {
                    appState.startAutomation()
                }
            } label: {
                Label(appState.automationRunning ? "Stop" : "Start",
                      systemImage: appState.automationRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.automationRunning ? .red : .green)
            .accessibilityIdentifier("startStopButton")
            .help(appState.automationRunning ? "Stop the running automation loop" : "Start matching the screen and firing actions")

            Button {
                appState.presentAddAction()
            } label: {
                Label("Add Action", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("addActionButton")
            .help("Open the action editor to add a new click to this project")

            Spacer()

            Text(appState.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("Latest engine status — what it just matched, fired, or is waiting on")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var bodySplit: some View {
        HSplitView {
            TimelineView(appState: appState)
                .frame(minWidth: 360, minHeight: 200)
            VStack(spacing: 0) {
                LivePreviewView(appState: appState)
                    .frame(maxWidth: .infinity, minHeight: 150, idealHeight: 250)
                Divider()
                LogView(appState: appState)
                    .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 180)
            }
            .frame(minWidth: 280, minHeight: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusPill: some View {
        let running = appState.automationRunning
        return HStack(spacing: 6) {
            Circle()
                .fill(running ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(running ? "Running" : "Idle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(running ? "The automation loop is actively matching and firing actions" : "The automation loop is stopped — press Start to begin")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(.regularMaterial)
        )
    }
}
