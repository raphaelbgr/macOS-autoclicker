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
                        HStack {
                            if let capturedImage {
                                PositionPickerView(image: capturedImage, x: $action.x, y: $action.y)
                                    .frame(maxHeight: 160)
                            } else {
                                ContentUnavailableBox(
                                    icon: "photo",
                                    title: "No reference yet",
                                    message: "Capture one to enable visual matching"
                                )
                                .frame(maxWidth: .infinity, minHeight: 120)
                            }
                        }

                        Button {
                            Task { await captureReference() }
                        } label: {
                            Label(isCapturing ? "Capturing…" : "Capture Now", systemImage: "camera.viewfinder")
                        }
                        .disabled(isCapturing || appState.settings.target == .iphoneMirroring && !ScreenCapture.hasScreenRecordingPermission)

                        LabeledContent("OCR text (comma = OR)") {
                            TextField("Victory, Game Over", text: $action.matchTexts)
                                .frame(maxWidth: 240)
                        }
                    }
                }

                Section("Click") {
                    LabeledContent("Position") {
                        HStack {
                            TextField("X", value: $action.x, format: .number.grouping(.never))
                                .frame(width: 60)
                            TextField("Y", value: $action.y, format: .number.grouping(.never))
                                .frame(width: 60)
                        }
                    }

                    Picker("Click type", selection: $action.clickType) {
                        Text("Single").tag(ClickType.single)
                        Text("Double").tag(ClickType.double)
                        Text("Long press").tag(ClickType.longPress)
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

                Section {
                    TextField("Label", text: $action.label, prompt: Text("Optional name"))
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
        .frame(width: 620, height: 660)
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
        defer { isCapturing = false }

        guard let window = ScreenCapture.resolveWindow(for: appState.settings.target) else {
            NSSound.beep()
            return
        }
        guard let cg = ScreenCapture.captureWindow(window) else {
            NSSound.beep()
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
