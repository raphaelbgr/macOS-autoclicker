//
//  MainWindow.swift
//  macOS AutoClicker
//
//  Root shell. NavigationSplitView with a projects sidebar + a detail
//  view containing: target picker, toolbar with Start/Stop + Add, the
//  timeline list, live preview, and log.
//

import SwiftUI

struct MainWindow: View {
    @ObservedObject var appState: AppState
    @State private var sidebarSelection: String?
    @State private var showOnboarding = false
    @State private var showAdd = false

    var body: some View {
        NavigationSplitView {
            // Sidebar: project list
            List(selection: $sidebarSelection) {
                Section("Projects") {
                    ForEach(appState.projects) { project in
                        NavigationLink(value: project.name) {
                            Label(project.name, systemImage: "folder")
                        }
                    }
                }
            }
            .navigationTitle("macOS OCR AutoClicker")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        appState.newProject()
                        sidebarSelection = appState.selectedProjectName
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                }
            }
            .frame(minWidth: 200)
        } detail: {
            if let name = appState.selectedProjectName {
                detailView(for: name)
            } else {
                Group {
                    if #available(macOS 14.0, *) {
                        ContentUnavailableView(
                            "No project selected",
                            systemImage: "tray",
                            description: Text("Create a project to get started.")
                        )
                    } else {
                        ContentUnavailableBox(
                            icon: "tray",
                            title: "No project selected",
                            message: "Create a project to get started"
                        )
                    }
                }
            }
        }
        .onChange(of: sidebarSelection) { new in
            if let new { appState.selectProject(new) }
        }
        .onAppear {
            sidebarSelection = appState.selectedProjectName
            // First-launch onboarding.
            if !UserDefaults.standard.bool(forKey: "hasCompletedPermissionOnboarding") {
                showOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            PermissionOnboardingSheet(appState: appState)
        }
    }

    @ViewBuilder
    private func detailView(for name: String) -> some View {
        VStack(spacing: 0) {
            // Header strip
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(name).font(.title3.bold())
                        TargetPickerView(appState: appState)
                    }
                    Spacer()
                    // Status pill
                    statusPill
                        .padding(.top, 4)
                }
            }
            .padding()
            .background(.bar)

            Divider()

            // Toolbar with Start/Stop + Add
            HStack(spacing: 8) {
                if appState.automationRunning {
                    Button {
                        appState.stopAutomation()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .glassButton(tint: .red)
                } else {
                    Button {
                        appState.startAutomation()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .glassButton(tint: .green)
                }

                Button {
                    showAdd = true
                } label: {
                    Label("Add Action", systemImage: "plus")
                }
                .glassButton()

                Spacer()

                Text(appState.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Body: timeline on left, preview+log on right
            HSplitView {
                TimelineView(appState: appState)
                    .frame(minWidth: 360)
                VStack(spacing: 0) {
                    LivePreviewView(appState: appState)
                        .frame(maxWidth: .infinity, minHeight: 200, idealHeight: 280)
                    Divider()
                    LogView(appState: appState)
                        .frame(maxWidth: .infinity, minHeight: 140, idealHeight: 200)
                }
                .frame(minWidth: 280)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Label("Add Action", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            ActionEditorSheet(appState: appState, isPresented: $showAdd, editIndex: nil)
        }
    }

    private var statusPill: some View {
        let running = appState.automationRunning
        return HStack(spacing: 6) {
            Circle()
                .fill(running ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .scaleEffect(running ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: running)
            Text(running ? "Running" : "Idle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassCard(cornerRadius: 999)
    }
}
