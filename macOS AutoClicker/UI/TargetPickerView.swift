//
//  TargetPickerView.swift
//  macOS AutoClicker
//
//  Lets the user pick what the active project targets: a window, a screen
//  region, a full display, or the iPhone Mirroring preset.
//

import SwiftUI
import CoreGraphics

struct TargetPickerView: View {
    @ObservedObject var appState: AppState
    @State private var windows: [CapturedWindow] = []
    @State private var pickingRegion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Target type", selection: selectedKindBinding) {
                Label("iPhone Mirroring", systemImage: "iphone.radiowaves.left.and.right").tag(TargetKind.iphoneMirroring)
                Label("Window", systemImage: "macwindow").tag(TargetKind.window)
                Label("Region", systemImage: "rectangle.dashed").tag(TargetKind.region)
                Label("Full Screen", systemImage: "display").tag(TargetKind.fullScreen)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("targetPicker")

            switch selectedKind {
            case .iphoneMirroring:
                Text("Locks to the iPhone Mirroring window when present. Unlocks Home / App Switcher / Spotlight / Open / Close app actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .window:
                HStack {
                    Picker("Window", selection: windowSelectionBinding) {
                        Text("— Select a window —").tag(Optional<CapturedWindow>.none)
                        ForEach(filteredWindows) { w in
                            Text(displayName(w)).tag(Optional(w))
                        }
                    }
                    Button {
                        refreshWindows()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh window list")
                }

            case .region:
                Button {
                    Task {
                        pickingRegion = true
                        let rect = await RegionPicker.pick()
                        pickingRegion = false
                        if let rect {
                            setTarget(.region(rect))
                        }
                    }
                } label: {
                    Label(pickingRegion ? "Drag on screen…" : "Draw Region", systemImage: "crop")
                }
                .buttonStyle(.bordered)
                .disabled(pickingRegion)
                if case .region(let r) = appState.settings.target {
                    Text(formatRect(r))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

            case .fullScreen:
                Picker("Display", selection: displaySelectionBinding) {
                    ForEach(activeDisplays, id: \.self) { did in
                        Text("Display \(did)").tag(did)
                    }
                }
            }
        }
        .onAppear { refreshWindows() }
    }

    // MARK: - Helpers

    enum TargetKind: Hashable {
        case iphoneMirroring, window, region, fullScreen
    }

    private var selectedKind: TargetKind {
        switch appState.settings.target {
        case .iphoneMirroring: return .iphoneMirroring
        case .window:          return .window
        case .region:          return .region
        case .fullScreen:      return .fullScreen
        }
    }

    private var selectedKindBinding: Binding<TargetKind> {
        Binding(
            get: { selectedKind },
            set: { newKind in
                let newTarget: TargetSpec
                switch newKind {
                case .iphoneMirroring: newTarget = .iphoneMirroring
                case .window:
                    let first = filteredWindows.first
                    newTarget = .window(owner: first?.ownerName ?? "", windowID: first?.windowID ?? 0)
                case .region:
                    newTarget = .region(CGRect(x: 0, y: 0, width: 400, height: 400))
                case .fullScreen:
                    newTarget = .fullScreen(CGMainDisplayID())
                }
                setTarget(newTarget)
            }
        )
    }

    private var windowSelectionBinding: Binding<CapturedWindow?> {
        Binding(
            get: {
                if case .window(let owner, let wid) = appState.settings.target {
                    return windows.first(where: { $0.ownerName == owner && $0.windowID == wid })
                }
                return nil
            },
            set: { selected in
                if let selected {
                    setTarget(.window(owner: selected.ownerName, windowID: selected.windowID))
                }
            }
        )
    }

    private var displaySelectionBinding: Binding<CGDirectDisplayID> {
        Binding(
            get: {
                if case .fullScreen(let did) = appState.settings.target { return did }
                return CGMainDisplayID()
            },
            set: { did in setTarget(.fullScreen(did)) }
        )
    }

    private func setTarget(_ target: TargetSpec) {
        var s = appState.settings
        s.target = target
        appState.setSettings(s)
    }

    private var filteredWindows: [CapturedWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windows.filter { $0.ownerPID != ownPID }
    }

    private var activeDisplays: [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var actual: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &actual)
        return Array(ids.prefix(Int(actual)))
    }

    private func refreshWindows() {
        windows = ScreenCapture.listWindows()
    }

    private func displayName(_ w: CapturedWindow) -> String {
        if w.windowName.isEmpty {
            return w.ownerName
        }
        return "\(w.ownerName) — \(w.windowName)"
    }

    private func formatRect(_ r: CGRect) -> String {
        String(format: "(%.0f, %.0f) %.0f×%.0f", r.origin.x, r.origin.y, r.width, r.height)
    }
}
