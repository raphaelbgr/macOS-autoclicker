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
    @State private var editTarget: EditTarget?
    @State private var sortByActivity = false

    /// Actions in display order. When "Sort by activity" is on, the most
    /// recently matched actions float to the top (by AppState.activityOrder);
    /// everything else keeps its natural order. `offset` is the real timeline
    /// index (used for editing/deleting/scores).
    private var displayedActions: [(offset: Int, element: ClickAction)] {
        let base = appState.timeline.actions.enumerated().map { (offset: $0.offset, element: $0.element) }
        guard sortByActivity else { return base }
        let rank = Dictionary(uniqueKeysWithValues:
            appState.activityOrder.enumerated().map { ($0.element, $0.offset) })
        return base.sorted { a, b in
            let ra = rank[a.element.id] ?? Int.max
            let rb = rank[b.element.id] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }
    }

    /// Identifiable wrapper so the editor is presented via `.sheet(item:)` —
    /// that rebuilds the sheet (and re-seeds its @State) for the exact action
    /// each time. `.sheet(isPresented:)` captured a stale/nil seed, so the
    /// editor opened blank when editing an existing action.
    private struct EditTarget: Identifiable { let id: Int }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Toggle(isOn: $sortByActivity.animation(.easeInOut(duration: 0.35))) {
                    Label("Sort by activity", systemImage: "bolt.fill")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Float the most recently matched action to the top as it fires")
                .accessibilityIdentifier("sortByActivitySwitch")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            list
        }
    }

    private var list: some View {
        List {
            ForEach(displayedActions, id: \.element.id) { item in
                actionRow(idx: item.offset, action: item.element)
                    .tag(item.offset)
            }
            .onDelete { offsets in
                let real = offsets.map { displayedActions[$0].offset }
                for i in real.sorted(by: >) {
                    appState.removeAction(at: i)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.activityOrder)
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
        .sheet(item: $editTarget) { target in
            ActionEditorSheet(
                appState: appState,
                isPresented: Binding(
                    get: { editTarget != nil },
                    set: { if !$0 { editTarget = nil } }
                ),
                editIndex: target.id,
                seed: appState.timeline.actions.indices.contains(target.id)
                    ? appState.timeline.actions[target.id] : nil
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

            Button {
                editTarget = EditTarget(id: idx)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit this action")
            .accessibilityIdentifier("editActionButton")

            Toggle("", isOn: enabledBinding(at: idx))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(appState.justFiredID == action.id ? 0.28 : 0))
                .animation(.easeInOut(duration: 0.5), value: appState.justFiredID)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editTarget = EditTarget(id: idx)
        }
        .help("Double-click or use the pencil to edit")
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
}
