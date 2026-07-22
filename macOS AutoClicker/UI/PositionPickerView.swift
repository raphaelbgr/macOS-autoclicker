//
//  PositionPickerView.swift
//  macOS AutoClicker
//
//  Click-on-image coordinate picker. Replaces PyQt6 ClickPositionPicker.
//  Displays a reference screenshot and lets the user click to set the
//  click target (x, y). A single SF-Symbol "scope" reticle marks the
//  selected point; position changes are undoable/redoable. Cancel on the
//  editor sheet still discards everything (edits live on the sheet's copy).
//

import SwiftUI
import AppKit

struct PositionPickerView: View {
    let image: NSImage
    @Binding var x: Int
    @Binding var y: Int
    @State private var imageSize: CGSize = .zero
    @State private var displayedSize: CGSize = .zero
    /// Position history for Undo/Redo. Each entry is a previous (x, y).
    @State private var undoStack: [(x: Int, y: Int)] = []
    @State private var redoStack: [(x: Int, y: Int)] = []

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .disabled(undoStack.isEmpty)
                .help("Undo the last click-position change")
                .accessibilityIdentifier("positionUndoButton")

                Button(action: redo) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.borderless)
                .disabled(redoStack.isEmpty)
                .help("Redo a position change you just undid")
                .accessibilityIdentifier("positionRedoButton")

                Spacer()

                Text("x \(x)  ·  y \(y)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .help("Current click target in reference-image pixel coordinates")
            }

            imageArea
        }
    }

    private var imageArea: some View {
        GeometryReader { geo in
            ZStack {
                let fit = aspectFitSize(image.size, in: geo.size)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fit.width, height: fit.height)
                    .background(Color.black.opacity(0.05))
                    .overlay(crosshairOverlay)
                    .contentShape(Rectangle())
                    .help("Reference screenshot — click any point to set where this action’s click lands; the reticle shows the current target")
                    .onTapGesture { loc in
                        guard imageSize.width > 0 else { return }
                        let scaleX = imageSize.width / fit.width
                        let scaleY = imageSize.height / fit.height
                        // loc is relative to the image frame (top-left origin
                        // in SwiftUI). Convert to image pixel coords.
                        let imgX = Int(loc.x * scaleX)
                        let imgY = Int(loc.y * scaleY)
                        undoStack.append((x: x, y: y))
                        redoStack.removeAll()
                        x = max(0, min(Int(imageSize.width), imgX))
                        y = max(0, min(Int(imageSize.height), imgY))
                    }
            }
            .onAppear {
                imageSize = image.size
                displayedSize = geo.size
            }
        }
        .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
        .frame(maxHeight: 440)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
    }

    private func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append((x: x, y: y))
        x = prev.x
        y = prev.y
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((x: x, y: y))
        x = next.x
        y = next.y
    }

    private func aspectFitSize(_ input: CGSize, in box: CGSize) -> CGSize {
        let scale = min(box.width / input.width, box.height / input.height)
        return CGSize(width: input.width * scale, height: input.height * scale)
    }

    /// Single precise reticle at the selected (x, y): the system "scope"
    /// symbol (macOS's own crosshair glyph), red with a soft white halo so it
    /// reads on any screenshot content.
    @ViewBuilder
    private var crosshairOverlay: some View {
        if imageSize.width > 0 && imageSize.height > 0 {
            GeometryReader { geo in
                let fit = aspectFitSize(image.size, in: geo.size)
                let scaleX = fit.width / imageSize.width
                let scaleY = fit.height / imageSize.height
                let cx = CGFloat(x) * scaleX
                let cy = CGFloat(y) * scaleY
                Image(systemName: "scope")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.red)
                    .shadow(color: .white.opacity(0.9), radius: 1.5)
                    .position(x: cx, y: cy)
                    .allowsHitTesting(false)
                    .help("Marks the current click target — click elsewhere on the image to move it")
            }
        }
    }
}
