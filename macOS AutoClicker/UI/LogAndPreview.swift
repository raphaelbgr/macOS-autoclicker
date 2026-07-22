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
    /// Re-creating the ripple view (via .id) on each fire re-runs its
    /// onAppear animation, giving us a one-shot ripple without timers.
    @State private var rippleID: UUID = UUID()

    var body: some View {
        VStack {
            if let previewImage {
                GeometryReader { geo in
                    let fit = aspectFitSize(previewImage.size, in: geo.size)
                    ZStack {
                        Image(nsImage: previewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: fit.width, height: fit.height)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))

                        // Fired-click marker, anchored ON the image at the
                        // exact click spot. The mapping is computed live from
                        // the current fit geometry (points → retina pixels →
                        // displayed frame) so it can never use stale sizes.
                        if let fired = appState.lastFiredPoint {
                            let pointScale = NSScreen.main?.backingScaleFactor ?? 2.0
                            let sx = fit.width / previewImage.size.width
                            let sy = fit.height / previewImage.size.height
                            let p = CGPoint(
                                x: min(max(0, fired.x * pointScale * sx), fit.width),
                                y: min(max(0, fired.y * pointScale * sy), fit.height)
                            )
                            FiredRippleOverlay(point: p)
                                .id(rippleID)
                                .allowsHitTesting(false)
                                .accessibilityIdentifier("firedRipple")
                        }

                        // "Fired: <label> at (x, y)" caption fading with the
                        // appState.lastFiredPoint lifecycle (~1.2s).
                        VStack {
                            Spacer()
                            firedCaption
                                .padding(.bottom, 6)
                        }
                        .frame(width: fit.width, height: fit.height)
                        .allowsHitTesting(false)
                    }
                    .frame(width: fit.width, height: fit.height)
                }
                .aspectRatio(previewImage.size.width / previewImage.size.height, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .help("Most recent screen capture from the running automation — refreshes about once a second; the ripple marks where the latest fired action clicked")
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
        .onChange(of: appState.lastFiredPoint) { new in
            // Re-create the ripple view on each fire so its one-shot
            // animation replays; position is computed live in the body.
            if new != nil { rippleID = UUID() }
        }
    }

    /// Small floating caption pinned to the bottom of the preview showing
    /// what just fired and where. Opacity tracks appState.lastFiredPoint
    /// (cleared ~1.2s after the latest fire by AppState) — pure implicit
    /// animation, no per-view timer.
    @ViewBuilder
    private var firedCaption: some View {
        let visible = appState.lastFiredPoint != nil && !appState.lastFiredLabel.isEmpty
        let point = appState.lastFiredPoint
        Text("Fired: \(appState.lastFiredLabel)" +
             (point.map { " at (\(Int($0.x)), \(Int($0.y)))" } ?? ""))
            .font(.caption.monospaced())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                    .fill(.ultraThinMaterial)
            )
            .opacity(visible ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.25), value: appState.lastFiredPoint)
            .help("Label and pixel coordinates of the most recently fired action — fades out about 1.2 seconds after the click")
    }

    private func capture() {
        // Same path the engine uses: window-based targets need a resolved
        // window; Region/Full-Screen capture without one. (resolveWindow
        // returns nil for region/fullScreen, so requiring it here left the
        // preview permanently empty on those targets.)
        let target = appState.settings.target
        let window = ScreenCapture.resolveWindow(for: target)
        let needsWindow: Bool
        switch target {
        case .iphoneMirroring, .window: needsWindow = true
        case .region, .fullScreen:      needsWindow = false
        }
        if needsWindow && window == nil {
            previewImage = nil
            return
        }
        guard let cg = ScreenCapture.capture(for: target, resolvedWindow: window) else {
            previewImage = nil
            return
        }
        previewImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Same aspect-fit math PositionPickerView uses (see PositionPickerView).
    private func aspectFitSize(_ input: CGSize, in box: CGSize) -> CGSize {
        let scale = min(box.width / input.width, box.height / input.height)
        return CGSize(width: input.width * scale, height: input.height * scale)
    }
}

/// One-shot ripple: a solid accent dot plus two expanding, fading ring
/// strokes. Stagger + expand + fade are all implicit `.easeOut` animations
/// fired from `.onAppear`, so re-creating the view (parent uses `.id(...)`)
/// replays the ripple on every fire.
private struct FiredRippleOverlay: View {
    let point: CGPoint

    // Ring start state (small + opaque). Animated to expanded + transparent.
    @State private var ringScale: CGFloat = 0.2
    @State private var ringOpacity: Double = 1.0
    @State private var ring2Scale: CGFloat = 0.2
    @State private var ring2Opacity: Double = 1.0

    private let baseSize: CGFloat = 14
    private let expandedScale: CGFloat = 4.0

    var body: some View {
        ZStack {
            // Ring 1 — expands and fades over 0.9s.
            Circle()
                .stroke(Color.red, lineWidth: 2.5)
                .frame(width: baseSize, height: baseSize)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            // Ring 2 — same shape, delayed 0.15s, slightly shorter so both
            // finish inside the ~0.9s total budget.
            Circle()
                .stroke(Color.red.opacity(0.6), lineWidth: 2.5)
                .frame(width: baseSize, height: baseSize)
                .scaleEffect(ring2Scale)
                .opacity(ring2Opacity)

            // Precise reticle pinned at the exact click point for the whole
            // marker lifetime (rings animate around it).
            Image(systemName: "scope")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.red)
                .shadow(color: .white.opacity(0.9), radius: 1.5)
        }
        .position(x: point.x, y: point.y)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) {
                ringScale = expandedScale
                ringOpacity = 0.0
            }
            withAnimation(.easeOut(duration: 0.75).delay(0.15)) {
                ring2Scale = expandedScale
                ring2Opacity = 0.0
            }
        }
    }
}
