//
//  TimelineView.swift
//  macOS AutoClicker
//
//  The action list. Each row shows a thumbnail, label, live similarity
//  bar, enabled toggle, and edit/delete affordances. Replaces the PyQt6
//  timeline table.
//

import SwiftUI
import AppKit

struct TimelineView: View {
    @ObservedObject var appState: AppState
    @State private var editingIndex: Int?
    @State private var showEditor = false

    var body: some View {
        List {
            ForEach(Array(appState.timeline.actions.enumerated()), id: \.element.id) { idx, action in
                actionRow(idx: idx, action: action)
                    .tag(idx)
            }
            .onDelete { offsets in
                for i in offsets.sorted(by: >) {
                    appState.removeAction(at: i)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .overlay {
            if appState.timeline.actions.isEmpty {
                // ContentUnavailableView is macOS 14+; fall back to our
                // own ContentUnavailableBox for macOS 13.
                if #available(macOS 14.0, *) {
                    ContentUnavailableView(
                        "No actions yet",
                        systemImage: "cursorarrow.motionlines",
                        description: Text("Click **+** to add a click action. Each action triggers when the screen matches its reference.")
                    )
                } else {
                    ContentUnavailableBox(
                        icon: "cursorarrow.motionlines",
                        title: "No actions yet",
                        message: "Click + to add a click action"
                    )
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            ActionEditorSheet(
                appState: appState,
                isPresented: $showEditor,
                editIndex: editingIndex,
                seed: editingIndex.map { appState.timeline.actions[$0] }
            )
        }
    }

    @ViewBuilder
    private func actionRow(idx: Int, action: ClickAction) -> some View {
        HStack(spacing: 12) {
            // Number badge / highlight
            ZStack {
                Circle()
                    .fill(appState.lastFiredIndex == idx ? Color.accentColor.opacity(0.25) : Color.clear)
                Text("\(idx + 1)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 26, height: 26)

            thumbnail(for: action)

            VStack(alignment: .leading, spacing: 4) {
                Text(action.label.isEmpty ? "Action \(idx + 1)" : action.label)
                    .font(.body.weight(.medium))
                    .strikethrough(!action.enabled)

                similarityBar(for: idx, action: action)
            }

            Spacer(minLength: 8)

            metaLabel(action: action)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Toggle("", isOn: enabledBinding(at: idx))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editingIndex = idx
            showEditor = true
        }
        .help("Double-click to edit")
    }

    @ViewBuilder
    private func thumbnail(for action: ClickAction) -> some View {
        if !action.screenshotPath.isEmpty,
           let name = appState.selectedProjectName,
           let img = Project(name: name).loadActionScreenshot(pathOrName: action.screenshotPath) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if !action.ocrPatterns.isEmpty {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    VStack(spacing: 0) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 16))
                        Text("OCR").font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(.tint)
                )
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "questionmark").foregroundStyle(.secondary))
        }
    }

    @ViewBuilder
    private func similarityBar(for idx: Int, action: ClickAction) -> some View {
        let sim = appState.similarities[idx] ?? 0
        let isMatch = sim >= action.threshold
        HStack(spacing: 8) {
            ProgressView(value: sim, total: 1.0)
                .progressViewStyle(.linear)
                .tint(isMatch ? .green : .accentColor)
                .frame(maxWidth: 220)
            Text("\(Int(sim * 100))%")
                .font(.caption.monospaced())
                .foregroundStyle(isMatch ? .green : .secondary)
                .frame(width: 36, alignment: .leading)
        }
    }

    private func metaLabel(action: ClickAction) -> some View {
        var bits: [String] = []
        bits.append(action.clickType.rawValue)
        if action.repeatCount > 1 { bits.append("×\(action.repeatCount)") }
        if action.delayMs > 0 { bits.append("+\(action.delayMs)ms") }
        if action.actionType != .click { bits.append(action.actionType.rawValue) }
        return Text(bits.joined(separator: " · "))
    }

    private func enabledBinding(at idx: Int) -> Binding<Bool> {
        Binding(
            get: { appState.timeline.actions[idx].enabled },
            set: { newValue in
                var a = appState.timeline.actions[idx]
                a.enabled = newValue
                appState.updateAction(at: idx, with: a)
            }
        )
    }

    func addNew() {
        editingIndex = nil
        showEditor = true
    }
}
