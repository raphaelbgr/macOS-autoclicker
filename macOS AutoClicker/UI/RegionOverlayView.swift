//
//  RegionOverlayView.swift
//  macOS AutoClicker
//
//  Transparent fullscreen overlay for drawing a screen rectangle, like
//  macOS's screenshot region selector. Hosts via NSPanel and returns the
//  selected CGRect via a continuation.
//

import AppKit
import SwiftUI

/// Presents a fullscreen crosshair overlay across all displays; resolves
/// to the user-drawn rectangle in global display coordinates.
enum RegionPicker {
    /// Show the overlay and await a selection.
    @MainActor
    static func pick() async -> CGRect? {
        await withCheckedContinuation { continuation in
            RegionOverlayController.present { rect in
                continuation.resume(returning: rect)
            }
        }
    }
}

/// Owns the borderless NSPanel windows (one per display) hosting the overlay.
@MainActor
private final class RegionOverlayController: NSObject, NSWindowDelegate {
    private static var current: RegionOverlayController?
    private var panels: [NSPanel] = []
    private var completion: ((CGRect?) -> Void)?
    private var startPoint: CGPoint?
    private var currentRect: CGRect = .zero
    private var trackingPanel: NSPanel?

    static func present(completion: @escaping (CGRect?) -> Void) {
        // Tear down any existing session first.
        current?.dismiss()
        let controller = RegionOverlayController()
        controller.completion = completion
        current = controller
        controller.show()
    }

    private func show() {
        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.ignoresMouseEvents = false
            panel.delegate = self

            let host = NSHostingView(
                rootView: RegionOverlaySwiftUIView(
                    onDrag: { [weak self] start, current in
                        self?.updateDrag(start: start, current: current)
                    },
                    onConfirm: { [weak self] in self?.confirm() },
                    onCancel: { [weak self] in self?.cancel() }
                )
            )
            host.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView = host
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func dismiss() {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        Self.current = nil
    }

    private func updateDrag(start: CGPoint, current: CGPoint) {
        startPoint = start
        currentRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private func confirm() {
        let result = currentRect.width > 4 && currentRect.height > 4 ? currentRect : nil
        let cb = completion
        dismiss()
        cb?(result)
    }

    private func cancel() {
        let cb = completion
        dismiss()
        cb?(nil)
    }

    // Pressing Escape cancels via key handling in the SwiftUI view below.
}

private struct RegionOverlaySwiftUIView: View {
    let onDrag: (CGPoint, CGPoint) -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var start: CGPoint?
    @State private var current: CGPoint?

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)

            if let s = start, let c = current {
                let rect = CGRect(
                    x: min(s.x, c.x), y: min(s.y, c.y),
                    width: abs(c.x - s.x), height: abs(c.y - s.y)
                )
                Rectangle()
                    .fill(.clear)
                    .border(.white.opacity(0.9), width: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                // Inverted dim outside selection.
                    .blendMode(.destinationOut)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .padding()
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if start == nil { start = value.startLocation }
                    current = value.location
                    onDrag(value.startLocation, value.location)
                }
                .onEnded { _ in onConfirm() }
        )
    }
}
