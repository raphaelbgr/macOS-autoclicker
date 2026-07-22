//
//  LogView.swift + LivePreviewView.swift
//  macOS AutoClicker
//
//  Two small views: the color-coded activity log and the live capture
//  preview. Kept in one file since both are short and conceptually paired.
//

import SwiftUI
import AppKit

// MARK: - LogView

struct LogView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.logEntries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                            Text("[\(entry.category.rawValue)]")
                                .font(.caption.monospaced())
                                .foregroundStyle(entry.category.color)
                            Text(entry.message)
                                .font(.caption.monospaced())
                            if let details = entry.details {
                                Text("· \(details)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        .onChange(of: appState.logEntries.last?.id) { _ in
            if let last = appState.logEntries.last {
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        }
        .background(.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small))
        .help("Activity log — each line records what the engine matched, fired, or skipped, newest at the bottom")
    }
}

// MARK: - LivePreviewView

struct LivePreviewView: View {
    @ObservedObject var appState: AppState
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    @State private var previewImage: NSImage?

    var body: some View {
        VStack {
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                    .help("Most recent screen capture from the running automation — refreshes about once a second")
            } else {
                ContentUnavailableBox(
                    icon: "eye.slash",
                    title: "No preview",
                    message: appState.automationRunning
                        ? "Captures will appear here while running"
                        : "Start automation to see live captures"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .help("Live preview is empty — it fills with screenshots once the automation engine starts capturing")
            }
        }
        .onReceive(timer) { _ in
            // Only update while running (saves CPU when idle).
            guard appState.automationRunning else { return }
            capture()
        }
    }

    private func capture() {
        guard let w = ScreenCapture.resolveWindow(for: appState.settings.target),
              let cg = ScreenCapture.captureWindow(w) else {
            previewImage = nil
            return
        }
        previewImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
