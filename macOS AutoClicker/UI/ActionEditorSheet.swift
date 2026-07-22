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
    /// OCR strings recognized on `capturedImage`. Refilled on every fresh
    /// capture and on initial load of an existing reference. Rendered as
    /// tappable chips below the OCR TextField.
    @State private var detectedTexts: [String] = []

    /// Gesture-first choices shown in the single Action picker. The first
    /// nine are plain mouse gestures (actionType == .click + a ClickType); the
    /// last two are the phone-only iPhone Mirroring commands kept for imported
    /// projects.
    private enum UIAction: Hashable {
        case click, doubleClick, tripleClick, rightClick, middleClick, longPress, drag, scrollUp, scrollDown, openApp, closeApp
    }

    private var uiAction: Binding<UIAction> {
        Binding(
            get: {
                switch action.actionType {
                case .openApp:  return .openApp
                case .closeApp: return .closeApp
                case .click:
                    switch action.clickType {
                    case .single:      return .click
                    case .double:      return .doubleClick
                    case .tripleClick: return .tripleClick
                    case .rightClick:  return .rightClick
                    case .middleClick: return .middleClick
                    case .longPress:   return .longPress
                    case .drag:        return .drag
                    case .scrollUp:    return .scrollUp
                    case .scrollDown:  return .scrollDown
                    }
                }
            },
            set: { new in
                switch new {
                case .click:       action.actionType = .click; action.clickType = .single
                case .doubleClick: action.actionType = .click; action.clickType = .double
                case .tripleClick: action.actionType = .click; action.clickType = .tripleClick
                case .rightClick:  action.actionType = .click; action.clickType = .rightClick
                case .middleClick: action.actionType = .click; action.clickType = .middleClick
                case .longPress:   action.actionType = .click; action.clickType = .longPress
                case .drag:        action.actionType = .click; action.clickType = .drag
                case .scrollUp:    action.actionType = .click; action.clickType = .scrollUp
                case .scrollDown:  action.actionType = .click; action.clickType = .scrollDown
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

    /// Whether this action lands somewhere on screen — i.e. its (x, y) matters,
    /// so the image-based position picker should be available.
    private var needsPosition: Bool {
        action.actionType == .click
            || (action.actionType == .openApp && action.openMethod == .tapIcon)
    }

    /// Timeline actions this one may follow (everything except itself),
    /// labeled for the After-action picker.
    private var otherActions: [(index: Int, title: String)] {
        appState.timeline.actions.enumerated().compactMap { i, a in
            guard i != editIndex else { return nil }
            return (index: i, title: a.label.isEmpty ? "Action \(i + 1)" : a.label)
        }
    }

    /// Keep afterIndex pointing at a real, non-self action so the picker never
    /// shows an empty selection.
    private func clampAfterIndex() {
        let valid = Set(otherActions.map { $0.index + 1 })
        if !valid.contains(action.afterIndex), let first = otherActions.first {
            action.afterIndex = first.index + 1
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(editIndex == nil ? "Add Action" : "Edit Action")
                    .font(.headline)
                    .help("Create a new click action or change the one currently being edited")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()

            Form {
                Section("Name") {
                    TextField("Label", text: $action.label, prompt: Text("Optional name"))
                        .help("A human-readable name shown in the timeline; leave blank to use “Action #N”")
                }

                Section("Action") {
                    Picker("Action", selection: uiAction) {
                        Text("Click").tag(UIAction.click)
                        Text("Double click").tag(UIAction.doubleClick)
                        Text("Triple click").tag(UIAction.tripleClick)
                        Text("Right click").tag(UIAction.rightClick)
                        Text("Middle click").tag(UIAction.middleClick)
                        Text("Long press").tag(UIAction.longPress)
                        Text("Drag").tag(UIAction.drag)
                        Text("Scroll up").tag(UIAction.scrollUp)
                        Text("Scroll down").tag(UIAction.scrollDown)
                        Divider()
                        Text("Open app (for iPhone Mirroring)").tag(UIAction.openApp)
                        Text("Close app (for iPhone Mirroring)").tag(UIAction.closeApp)
                    }
                    .help("Choose the gesture this action performs. Mouse interactions work on any target; the two app commands only run against the iPhone Mirroring window.")
                    if action.actionType != .click {
                        Label("Phone-only action: sends commands to the mirrored iPhone (Spotlight / App Switcher). Runs only with the iPhone Mirroring target — skipped on Window/Region/Full-Screen.",
                              systemImage: "iphone")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.Status.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .help("These commands target iOS, not macOS — they are ignored unless the project target is set to iPhone Mirroring")
                    }
                    if action.clickType == .scrollUp || action.clickType == .scrollDown {
                        Text("Scrolls 5 lines per repeat — use Repeat count for more.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Each repeat scrolls five lines; raise the Repeat count below to scroll further in one go")
                    }
                }

                Section("Trigger") {
                    Picker("Type", selection: $action.triggerType) {
                        Text("When screen matches").tag(TriggerType.recognition)
                        Text("After another action").tag(TriggerType.afterTrigger)
                    }
                    .help("“When screen matches” fires when the live screen reaches the threshold against this action’s reference; “After another action” fires a set time after a sibling action runs.")
                    .onChange(of: action.triggerType) { new in
                        if new == .afterTrigger && action.afterIndex < 1 { action.afterIndex = 1 }
                    }

                    if action.triggerType == .afterTrigger {
                        if otherActions.isEmpty {
                            Text("No other actions in the timeline yet — add the action this one should follow first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("An “After another action” trigger needs at least one other action to follow")
                        } else {
                            Picker("After action", selection: $action.afterIndex) {
                                ForEach(otherActions, id: \.index) { item in
                                    Text("#\(item.index + 1) — \(item.title)").tag(item.index + 1)
                                }
                            }
                            .help("The action this one follows: when that action fires, this one runs after its own delay")
                            .accessibilityIdentifier("afterActionPicker")
                            .onAppear(perform: clampAfterIndex)
                        }
                    }

                    if action.triggerType == .recognition {
                    LabeledContent("Threshold") {
                        HStack {
                            Slider(value: $action.threshold, in: 0...1, step: 0.05)
                                .frame(maxWidth: 220)
                                .help("Minimum similarity (0–100%) the live screen must reach against the reference for this action to fire")
                            Text("\(Int(action.threshold * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                                .help("Current similarity cutoff as a percentage — lower matches more loosely, higher demands a near-exact match")
                        }
                    }
                    .help("How closely the live screen must resemble the reference screenshot before this action fires")
                    }

                    LabeledContent("Delay before click") {
                        Stepper(value: $action.delayMs, in: 0...60_000, step: 100) {
                            TextField("ms", value: $action.delayMs, format: .number.grouping(.never))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .help("Wait this many milliseconds after a match before the click is sent — useful when a UI element needs time to become tappable")
                }

                // Shown whenever the action needs a reference image: for
                // matching (recognition trigger, any action kind) and/or for
                // aiming the click position on a screenshot (any positional
                // gesture, including after-trigger ones and Open-app tap-icon).
                if action.triggerType == .recognition || needsPosition {
                    Section(action.triggerType == .recognition ? "Reference screenshot" : "Click position") {
                        if let capturedImage {
                            PositionPickerView(image: capturedImage, x: $action.x, y: $action.y)
                                .frame(maxWidth: .infinity)
                                .help("Click anywhere on this image to set the click target — the reticle marks the current position")
                        } else {
                            ContentUnavailableBox(
                                icon: "photo",
                                title: "No reference yet",
                                message: action.triggerType == .recognition
                                    ? "Capture one to enable visual matching"
                                    : "Capture one to aim the click position on a screenshot"
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                        }

                        Button {
                            Task { await captureReference() }
                        } label: {
                            Label(isCapturing ? "Capturing…" : "Capture Now", systemImage: "camera.viewfinder")
                        }
                        .disabled(isCapturing || !ScreenCapture.hasScreenRecordingPermission)
                        .help("Grab a fresh screenshot of the current target — used as the visual match reference and to aim the click; requires Screen Recording permission")

                        if let captureError {
                            Label(captureError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.Status.warning)
                                .fixedSize(horizontal: false, vertical: true)
                                .help("The last capture attempt failed — follow the message, then try Capture Now again")
                        }

                        if action.triggerType == .recognition {
                            LabeledContent("When text detected (OCR)") {
                                TextField("eg: Game Over, Next", text: $action.matchTexts)
                                    .frame(maxWidth: 240)
                                    .accessibilityIdentifier("ocrTextField")
                                    .help("Comma-separated words/phrases; the action also fires when on-screen OCR reads any of them")
                            }
                            Text("Fires when any of these texts is read on screen. Separate alternatives with commas.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("OCR runs every monitor cycle; listing several alternatives lets one action cover a few wordings")

                            // OCR suggestion chips: detected phrases that the
                            // user can append with a click. The TextField above
                            // stays fully editable — chips only insert text.
                            if !detectedTexts.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Detected in reference — click to add:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .help("Phrases Vision recognized on the reference screenshot; tap one to append it to the OCR field above")
                                    LazyVGrid(
                                        columns: [GridItem(.adaptive(minimum: 90), spacing: 6)],
                                        alignment: .leading,
                                        spacing: 6
                                    ) {
                                        ForEach(detectedTexts, id: \.self) { text in
                                            Button {
                                                addChip(text)
                                            } label: {
                                                Text(text)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(
                                                        Capsule().fill(Color.accentColor.opacity(0.15))
                                                    )
                                                    .overlay(
                                                        Capsule().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 0.5)
                                                    )
                                                    .foregroundStyle(.primary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Append “\(text)” to the OCR match field")
                                            .accessibilityIdentifier("ocrDetectedChip")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if action.actionType == .click {
                Section("Click") {
                    LabeledContent("Position") {
                        HStack {
                            TextField("X", value: $action.x, format: .number.grouping(.never))
                                .frame(width: 60)
                                .help("Horizontal click coordinate in pixels, measured from the target’s top-left corner")
                            TextField("Y", value: $action.y, format: .number.grouping(.never))
                                .frame(width: 60)
                                .help("Vertical click coordinate in pixels, measured from the target’s top-left corner")
                        }
                    }
                    .help("Where the gesture lands, in pixels relative to the target window or region")

                    if action.clickType == .drag {
                        LabeledContent("End position") {
                            HStack {
                                TextField("X", value: $action.endX, format: .number.grouping(.never))
                                    .frame(width: 60)
                                    .help("Horizontal pixel coordinate where the drag releases (relative to the target’s top-left corner)")
                                TextField("Y", value: $action.endY, format: .number.grouping(.never))
                                    .frame(width: 60)
                                    .help("Vertical pixel coordinate where the drag releases (relative to the target’s top-left corner)")
                            }
                        }
                        .help("The point the cursor is dragged to — Position above is the start, this is the drop point")
                    }

                    if action.clickType == .longPress {
                        LabeledContent("Hold duration (ms)") {
                            Stepper(value: $action.durationMs, in: 50...3_600_000, step: 100) {
                                TextField("ms", value: $action.durationMs, format: .number.grouping(.never))
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .help("How long the mouse button is held down — set higher for press-and-hold menus or long-press gestures")
                    }

                    LabeledContent("Repeat count") {
                        Stepper(value: $action.repeatCount, in: 1...200) {
                            TextField("", value: $action.repeatCount, format: .number.grouping(.never))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                        }
                    }
                    .help("Send the gesture this many times per fire; the engine pauses ~50ms between repeats")
                }
                }

                if action.actionType == .closeApp {
                    Section("Close app") {
                        Picker("Method", selection: $action.closeMethod) {
                            Text("Force quit (App Switcher)").tag(CloseMethod.forceQuit)
                            Text("Home button").tag(CloseMethod.home)
                        }
                        .help("Force quit swipes the current app away in the iOS App Switcher; Home just exits to the home screen")
                    }
                }

                if action.actionType == .openApp {
                    Section("Open app") {
                        Picker("Method", selection: $action.openMethod) {
                            Text("Spotlight search").tag(OpenMethod.spotlight)
                            Text("Tap icon (x, y)").tag(OpenMethod.tapIcon)
                        }
                        .help("Spotlight types the app name into iOS search and presses return; Tap icon taps at this action’s Position")
                        if action.openMethod == .spotlight {
                            TextField("App name", text: $action.appName)
                                .help("Exact app name to type into iOS Spotlight (used only with the Spotlight method)")
                        }
                        if action.openMethod == .tapIcon {
                            LabeledContent("Tap position") {
                                HStack {
                                    TextField("X", value: $action.x, format: .number.grouping(.never))
                                        .frame(width: 60)
                                        .help("Horizontal pixel coordinate of the icon to tap, from the target’s top-left corner")
                                    TextField("Y", value: $action.y, format: .number.grouping(.never))
                                        .frame(width: 60)
                                        .help("Vertical pixel coordinate of the icon to tap, from the target’s top-left corner")
                                }
                            }
                            .help("Where the icon tap lands — aim it on the reference image above or type exact pixels")
                        }
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
                    .help("Discard all changes and close this sheet")
                Button(editIndex == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .help("Store this action in the active project’s timeline")
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
        runOCR()
    }

    /// Run Vision OCR on the current `capturedImage` off the main thread and
    /// refill `detectedTexts`. Deduped, trimmed, capped at 12 entries so the
    /// chip grid never overflows the sheet.
    private func runOCR() {
        guard let img = capturedImage,
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            detectedTexts = []
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let raw = OCRMatcher.recognizeText(in: cg)
            var seen = Set<String>()
            var cleaned: [String] = []
            for candidate in raw {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                if seen.insert(key).inserted {
                    cleaned.append(trimmed)
                }
                if cleaned.count >= 12 { break }
            }
            DispatchQueue.main.async {
                detectedTexts = cleaned
            }
        }
    }

    /// Append a detected-text chip to `action.matchTexts`. Skips if the same
    /// phrase (case-insensitive) is already in the list. Comma-joins with a
    /// leading space so the field stays human-readable.
    private func addChip(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = action.ocrPatterns.map { $0.lowercased() }
        guard !existing.contains(trimmed.lowercased()) else { return }
        if action.matchTexts.isEmpty {
            action.matchTexts = trimmed
        } else {
            action.matchTexts += ", \(trimmed)"
        }
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
        runOCR()

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
