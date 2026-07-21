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
                Spacer()
                Button {
                    appState.newProject()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New project")
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
                    TargetPickerView(appState: appState)
                }
                Spacer()
                statusPill
                    .padding(.top, 6)
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

            Button {
                appState.presentAddAction()
            } label: {
                Label("Add Action", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("addActionButton")

            Spacer()

            Text(appState.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(.regularMaterial)
        )
    }
}
