//
//  PermissionOnboardingSheet.swift
//  macOS AutoClicker
//
//  First-launch TCC prompt flow. Explains why we need each permission and
//  triggers the actual macOS prompt, then deep-links to System Settings
//  for the toggle step (TCC itself requires a manual user toggle).
//

import SwiftUI

struct PermissionOnboardingSheet: View {
    @ObservedObject var appState: AppState
    @AppStorage("hasCompletedPermissionOnboarding") private var hasCompleted = false
    @State private var screenRecordingRequested = false
    @State private var accessibilityRequested = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Two permissions to enable")
                    .font(.title2.bold())
                Text("macOS OCR AutoClicker needs these to capture windows and send clicks. Both run entirely on your Mac — no data ever leaves your system.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            permissionRow(
                icon: "rectangle.dashed.badge.record",
                title: "Screen Recording",
                description: "Capture the window or region you want to automate.",
                granted: ScreenCapture.hasScreenRecordingPermission,
                requested: screenRecordingRequested,
                actionTitle: "Open Settings",
                action: requestScreenRecording
            )

            permissionRow(
                icon: "hand.tap.fill",
                title: "Accessibility",
                description: "Send synthetic clicks to the target window.",
                granted: ClickExecutor.hasPostEventPermission,
                requested: accessibilityRequested,
                actionTitle: "Request Access",
                action: requestAccessibility
            )

            HStack(spacing: 12) {
                Button("Skip for now") { hasCompleted = true }
                    .buttonStyle(.bordered)
                Button("Done") { hasCompleted = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!allGranted)
                    .opacity(allGranted ? 1.0 : 0.5)
            }
        }
        .padding(32)
        .frame(width: 480)
        .glassCard()
        .background(.background)
    }

    private var allGranted: Bool {
        ScreenCapture.hasScreenRecordingPermission && ClickExecutor.hasPostEventPermission
    }

    private func requestScreenRecording() {
        // TCC requires the user to manually toggle in System Settings.
        // Triggering a capture attempt prompts the system to show the dialog
        // for the first time, then we deep-link.
        _ = ScreenCapture.listWindows()
        screenRecordingRequested = true
        openSystemSettings("Privacy & Security", paneID: "com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func requestAccessibility() {
        _ = ClickExecutor.requestPostEventPermission()
        accessibilityRequested = true
        openSystemSettings("Privacy & Security", paneID: "com.apple.preference.security?Privacy_Accessibility")
    }

    private func openSystemSettings(_ displayName: String, paneID: String) {
        if let url = URL(string: "x-apple.systempreferences:\(paneID)") {
            NSWorkspace.shared.open(url)
        }
    }

    @ViewBuilder
    private func permissionRow(
        icon: String, title: String, description: String,
        granted: Bool, requested: Bool,
        actionTitle: String, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .frame(width: 32)
                .foregroundStyle(granted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
}
