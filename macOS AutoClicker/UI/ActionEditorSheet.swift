//
//  ActionEditorSheet.swift
//  macOS AutoClicker
//
//  Add/edit action form. Replaces PyQt6 AddClickDialog. Lets the user
//  configure a single ClickAction: trigger type, threshold, delay, click
//  position + type, OCR patterns, repeat count. For iPhone Mirroring
//  targets, also exposes app-lifecycle actions (Home / Open / Close App).
//

import SwiftUI
import AppKit

struct ActionEditorSheet: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool

    /// Index of the action being edited, or nil for a new one.
    let editIndex: Int?

    @State private var action: ClickAction
    @State private var capturedImage: NSImage?
    @State private var isCapturing = false
    @State private var captureError: String?

    /// Gesture-first choices shown in the single Action picker. The first four
    /// are plain mouse gestures (actionType == .click + a ClickType); the last
    /// two are the phone-only iPhone Mirroring commands kept for imported
    /// projects.
    private enum UIAction: Hashable {
        case click, doubleClick, rightClick, longPress, openApp, closeApp
    }

    private var uiAction: Binding<UIAction> {
        Binding(
            get: {
                switch action.actionType {
                case .openApp:  return .openApp
                case .closeApp: return .closeApp
                case .click:
                    switch action.clickType {
                    case .single:     return .click
                    case .double:     return .doubleClick
                    case .rightClick: return .rightClick
                    case .longPress:  return .longPress
                    }
                }
            },
            set: { new in
                switch new {
                case .click:       action.actionType = .click; action.clickType = .single
                case .doubleClick: action.actionType = .click; action.clickType = .double
                case .rightClick:  action.actionType = .click; action.clickType = .rightClick
                case .longPress:   action.actionType = .click; action.clickType = .longPress
                case .openApp:     action.actionType = .openApp
                case .closeApp:    action.actionType = .closeApp
                }
            }
        )
    }

    init(appState: AppState, isPresented: Binding<Bool>, editIndex: Int?, seed: ClickAction? = nil) {
        self.appState = appState
        self._isPresented = isPresented
        self.editIndex = editIndex
        _action = State(initialValue: seed ?? ClickAction())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(editIndex == nil ? "Add Action" : "Edit Action")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()

            Form {
                Section("Name") {
                    TextField("Label", text: $action.label, prompt: Text("Optional name"))
                }

                Section("Action") {
                    Picker("Action", selection: uiAction) {
                        Text("Click").tag(UIAction.click)
                        Text("Double click").tag(UIAction.doubleClick)
                        Text("Right click").tag(UIAction.rightClick)
                        Text("Long press").tag(UIAction.longPress)
                        Divider()
                        Text("Open app (iPhone Mirroring)").tag(UIAction.openApp)
                        Text("Close app (iPhone Mirroring)").tag(UIAction.closeApp)
                    }
                    if action.actionType != .click {
                        Label("Phone-only action: sends commands to the mirrored iPhone (Spotlight / App Switcher). Runs only with the iPhone Mirroring target — skipped on Window/Region/Full-Screen.",
                              systemImage: "iphone")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.Status.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Trigger") {
                    Picker("Type", selection: $action.triggerType) {
                        Text("When screen matches").tag(TriggerType.recognition)
                        Text("After another action").tag(TriggerType.afterTrigger)
                    }
                    .onChange(of: action.triggerType) { new in
                        if new == .afterTrigger && action.afterIndex < 1 { action.afterIndex = 1 }
                    }

                    if action.triggerType == .afterTrigger {
                        Stepper("After action #\(action.afterIndex)", value: $action.afterIndex, in: 1...999)
                    }

                    LabeledContent("Threshold") {
                        HStack {
                            Slider(value: $action.threshold, in: 0...1, step: 0.05)
                                .frame(maxWidth: 220)
                            Text("\(Int(action.threshold * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }

                    LabeledContent("Delay before click") {
                        Stepper(value: $action.delayMs, in: 0...60_000, step: 100) {
                            TextField("ms", value: $action.delayMs, format: .number.grouping(.never))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if action.triggerType == .recognition {
                    Section("Reference screenshot") {
                        if let capturedImage {
                            PositionPickerView(image: capturedImage, x: $action.x, y: $action.y)
                                .frame(maxWidth: .infinity)
                        } else {
                            ContentUnavailableBox(
                                icon: "photo",
                                title: "No reference yet",
                                message: "Capture one to enable visual matching"
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                        }

                        Button {
                            Task { await captureReference() }
                        } label: {
                            Label(isCapturing ? "Capturing…" : "Capture Now", systemImage: "camera.viewfinder")
                        }
                        .disabled(isCapturing || !ScreenCapture.hasScreenRecordingPermission)

                        if let captureError {
                            Label(captureError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.Status.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        LabeledContent("When text detected (OCR)") {
                            TextField("eg: Game Over, Next", text: $action.matchTexts)
                                .frame(maxWidth: 240)
                                .accessibilityIdentifier("ocrTextField")
                        }
                        Text("Fires when any of these texts is read on screen. Separate alternatives with commas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if action.actionType == .click {
                Section("Click") {
                    LabeledContent("Position") {
                        HStack {
                            TextField("X", value: $action.x, format: .number.grouping(.never))
                                .frame(width: 60)
                            TextField("Y", value: $action.y, format: .number.grouping(.never))
                                .frame(width: 60)
                        }
                    }

                    if action.clickType == .longPress {
                        LabeledContent("Hold duration (ms)") {
                            Stepper(value: $action.durationMs, in: 50...3_600_000, step: 100) {
                                TextField("ms", value: $action.durationMs, format: .number.grouping(.never))
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }

                    LabeledContent("Repeat count") {
                        Stepper(value: $action.repeatCount, in: 1...200) {
                            TextField("", value: $action.repeatCount, format: .number.grouping(.never))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                        }
                    }
                }
                }

                if action.actionType == .closeApp {
                    Section("Close app") {
                        Picker("Method", selection: $action.closeMethod) {
                            Text("Force quit (App Switcher)").tag(CloseMethod.forceQuit)
                            Text("Home button").tag(CloseMethod.home)
                        }
                    }
                }

                if action.actionType == .openApp {
                    Section("Open app") {
                        Picker("Method", selection: $action.openMethod) {
                            Text("Spotlight search").tag(OpenMethod.spotlight)
                            Text("Tap icon (x, y)").tag(OpenMethod.tapIcon)
                        }
                        TextField("App name", text: $action.appName)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
                Button(editIndex == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 680, height: 780)
        .onAppear(perform: loadExistingReference)
    }

    /// Human-readable reason capture couldn't find a window, based on the target.
    private func captureTargetHint() -> String {
        switch appState.settings.target {
        case .iphoneMirroring:
            return "Open the iPhone Mirroring app with your device screen showing, then Capture again."
        case .window:
            return "The target window isn't open. Bring the target app to a visible window, then Capture again."
        case .region, .fullScreen:
            return "Capture failed for this target."
        }
    }

    /// When editing an existing action, load its reference screenshot from disk
    /// so the picker shows it instead of the empty "No reference yet" box.
    private func loadExistingReference() {
        guard capturedImage == nil, !action.screenshotPath.isEmpty,
              let name = appState.selectedProjectName else { return }
        capturedImage = Project(name: name).loadActionScreenshot(pathOrName: action.screenshotPath)
    }

    private func save() {
        if let editIndex {
            appState.updateAction(at: editIndex, with: action)
        } else {
            appState.addAction(action)
        }
        isPresented = false
    }

    private func captureReference() async {
        isCapturing = true
        captureError = nil
        defer { isCapturing = false }

        let target = appState.settings.target
        let window = ScreenCapture.resolveWindow(for: target)
        // Window-based targets need a resolvable window; region/full-screen don't.
        let needsWindow: Bool
        switch target {
        case .iphoneMirroring, .window: needsWindow = true
        case .region, .fullScreen:      needsWindow = false
        }
        if needsWindow && window == nil {
            NSSound.beep()
            captureError = captureTargetHint()
            return
        }
        guard let cg = ScreenCapture.capture(for: target, resolvedWindow: window) else {
            NSSound.beep()
            captureError = "Capture failed. Confirm Screen Recording is granted for this app, then try again."
            return
        }
        let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        capturedImage = ns

        // Persist the screenshot to the project folder and store its relative path.
        if let name = appState.selectedProjectName {
            let project = Project(name: name)
            if let relative = try? project.saveActionScreenshot(index: editIndex ?? appState.timeline.actions.count, image: ns) {
                action.screenshotPath = relative
            }
        }
    }
}

/// Small placeholder box for empty states.
struct ContentUnavailableBox: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
