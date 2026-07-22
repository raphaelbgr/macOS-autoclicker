//
//  SettingsView.swift
//  macOS AutoClicker
//
//  App-level preferences: monitor interval, match method, background-click
//  mode, and the global hotkey recorder (KeyboardShortcuts).
//

import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            hotkeyTab.tabItem { Label("Hotkey", systemImage: "keyboard") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 340)
    }

    @ViewBuilder
    private var generalTab: some View {
        Form {
            Section("Active project — \(appState.selectedProjectName ?? "none")") {
                LabeledContent("Match method") {
                    Picker("", selection: matchMethodBinding) {
                        Text("FeaturePrint (semantic)").tag(MatchMethod.featurePrint)
                        Text("SSIM (pixel-exact)").tag(MatchMethod.ssim)
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                    .help("FeaturePrint compares overall shape/layout (forgives small shifts); SSIM demands a near pixel-perfect match")
                }

                LabeledContent("Monitor interval") {
                    HStack {
                        Slider(value: intervalBinding, in: 100...2000, step: 50)
                            .frame(width: 180)
                            .help("How often the screen is re-captured and compared — lower is more responsive but uses more CPU")
                        Text("\(appState.settings.monitorIntervalMs) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                            .help("Current capture cadence in milliseconds")
                    }
                }

                LabeledContent("Default threshold") {
                    HStack {
                        Slider(value: thresholdBinding, in: 0.5...1.0, step: 0.05)
                            .frame(width: 180)
                            .help("Default similarity cutoff (50–100%) applied to new actions that don’t override it")
                        Text("\(Int(appState.settings.threshold * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                            .help("Current default cutoff as a percentage")
                    }
                }

                Toggle("Background click (ghost mode)", isOn: backgroundBinding)
                    .help("Snap cursor to target, click, restore — don’t visibly move the mouse")
            }

            Section("Privacy") {
                LabeledContent("Screen Recording") {
                    permissionPill(granted: ScreenCapture.hasScreenRecordingPermission)
                        .help("Required to capture the target window or region — check this is granted before running")
                }
                LabeledContent("Accessibility") {
                    permissionPill(granted: ClickExecutor.hasAccessibilityPermission)
                        .help("Required to send synthetic clicks — the app can’t interact with other windows without it")
                }
                Button("Open System Settings → Privacy & Security") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
                .help("Jump straight to the macOS Privacy & Security pane to review or grant permissions")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var hotkeyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Global Hotkey")
                .font(.headline)
                .help("A keyboard shortcut that starts or stops automation from any app, without switching to this window")
            Text("Trigger Start / Stop from anywhere on your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Once recorded, pressing the combo toggles the engine even when this app is in the background")
            KeyboardShortcuts.Recorder("Toggle automation:", name: .toggleAutomation)
                .help("Click here and press the key combo you want to assign as the global start/stop shortcut")
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)
            Text("macOS OCR AutoClicker")
                .font(.title2.bold())
            Text("version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")")
                .foregroundStyle(.secondary)
            Text("Native automation for any window, region, or full screen.")
                .font(.caption)
                .multilineTextAlignment(.center)
            Divider()
            VStack(spacing: 4) {
                Text("by Raphael BGR").font(.caption)
                Link("github.com/raphaelbgr/macOS-autoclicker",
                     destination: URL(string: "https://github.com/raphaelbgr/macOS-autoclicker")!)
                    .font(.caption)
                Text("All matching, OCR, and click logic runs locally.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    // MARK: - Bindings (route through to AppState.setSettings)

    private var matchMethodBinding: Binding<MatchMethod> {
        Binding(
            get: { appState.settings.matchMethod },
            set: { m in
                var s = appState.settings; s.matchMethod = m
                appState.setSettings(s)
            }
        )
    }

    private var intervalBinding: Binding<Double> {
        Binding(
            get: { Double(appState.settings.monitorIntervalMs) },
            set: { v in
                var s = appState.settings; s.monitorIntervalMs = Int(v)
                appState.setSettings(s)
            }
        )
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { appState.settings.threshold },
            set: { v in
                var s = appState.settings; s.threshold = v
                appState.setSettings(s)
            }
        )
    }

    private var backgroundBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.backgroundClick },
            set: { v in
                var s = appState.settings; s.backgroundClick = v
                appState.setSettings(s)
            }
        )
    }

    @ViewBuilder
    private func permissionPill(granted: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .help(granted ? "Granted — this permission is active" : "Not granted — open System Settings to enable it")
            Text(granted ? "Granted" : "Not granted")
                .font(.caption)
                .help(granted ? "macOS allows this capability" : "macOS is still blocking this capability")
        }
    }
}
