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
    /// Bound to MainWindow's overlay presentation, so setting this false
    /// actually hides the onboarding card.
    @Binding var isPresented: Bool
    @State private var screenRecordingRequested = false
    @State private var accessibilityRequested = false
    /// Cached permission status. Probed asynchronously on appear so the TCC
    /// calls (CGWindowListCopyWindowInfo / CGPreflightPostEventAccess) never
    /// run inside SwiftUI's synchronous body evaluation — those calls can
    /// block or trigger system prompts that stall the render under XCUITest.
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false

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
                granted: screenRecordingGranted,
                requested: screenRecordingRequested,
                actionTitle: "Open Settings",
                action: requestScreenRecording
            )

            permissionRow(
                icon: "hand.tap.fill",
                title: "Accessibility",
                description: "Send synthetic clicks to the target window.",
                granted: accessibilityGranted,
                requested: accessibilityRequested,
                actionTitle: "Request Access",
                action: requestAccessibility
            )

            executablePathSection

            reauthorizeNote

            HStack(spacing: 12) {
                Button("Skip for now") {
                    hasCompleted = true
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboardingSkipButton")
                Button("Done") {
                    hasCompleted = true
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allGranted)
                .opacity(allGranted ? 1.0 : 0.5)
            }
        }
        .padding(32)
        .frame(width: 480)
        .glassCard()
        .background(.background)
        .onAppear { probePermissions() }
        // Re-check when the user returns from System Settings, so a grant
        // registers immediately instead of showing a stale status.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            probePermissions()
        }
        // Light poll while onboarding is visible — Accessibility (AXIsProcessTrusted)
        // updates live, so this flips the row to Granted seconds after the toggle.
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            probePermissions()
        }
    }

    private var allGranted: Bool {
        screenRecordingGranted && accessibilityGranted
    }

    /// Probe TCC permissions on a background thread so the main thread (which
    /// drives both SwiftUI rendering and XCUITest's accessibility queries) is
    /// never blocked by CGWindowListCopyWindowInfo or CGPreflightPostEventAccess.
    private func probePermissions() {
        DispatchQueue.global(qos: .userInitiated).async {
            let sr = ScreenCapture.hasScreenRecordingPermission
            let ax = ClickExecutor.hasAccessibilityPermission
            DispatchQueue.main.async {
                screenRecordingGranted = sr
                accessibilityGranted = ax
            }
        }
    }

    /// Quit and relaunch. Screen Recording (and a stale grant after an app
    /// update) only take effect on a fresh launch, so this opens a new instance
    /// and terminates the current one.
    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
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

    // MARK: - Executable path display

    /// Path of the running .app bundle and its inner executable. Shown so the
    /// user can find the exact binary macOS needs added to the Accessibility
    /// and Screen Recording lists via the `+` flow in System Settings.
    private var bundlePath: String { Bundle.main.bundlePath }
    private var executablePath: String? { Bundle.main.executableURL?.path }

    @ViewBuilder
    private var executablePathSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("App location", systemImage: "folder")
                .font(.headline)

            Text("Use this exact path when adding the app to the System Settings permission list.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(bundlePath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let exec = executablePath, exec != bundlePath {
                    Text(exec)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(.regularMaterial)
            )

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("onboardingRevealInFinderButton")

                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(bundlePath, forType: .string)
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("onboardingCopyPathButton")
            }

            Text("If the app is not already listed: click +, press Cmd-Shift-G, paste the path above, then Open. Turn its switch ON.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Re-authorize note

    /// macOS binds a permission grant to a specific version of the app's code
    /// signature. After the app updates — or if a grant goes stale — the switch
    /// can read "on" while the current build is still denied, until the user
    /// toggles it off and on again. Surface that recovery step up front.
    @ViewBuilder
    private var reauthorizeNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.Status.warning)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("Switched on but still blocked?")
                    .font(.callout.weight(.semibold))
                Text("Screen Recording only takes effect after a restart, and a grant can go stale after the app updates. Quit and reopen — or in System Settings toggle the permission OFF and back ON to re-authorize it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    relaunchApp()
                } label: {
                    Label("Quit & Reopen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("onboardingQuitReopenButton")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(DesignTokens.Status.warning.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .strokeBorder(DesignTokens.Status.warning.opacity(0.28), lineWidth: 1)
        )
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
