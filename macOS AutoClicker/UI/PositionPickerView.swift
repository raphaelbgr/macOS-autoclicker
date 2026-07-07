//
//  PositionPickerView.swift
//  macOS AutoClicker
//
//  Click-on-image coordinate picker. Replaces PyQt6 ClickPositionPicker.
//  Displays a reference screenshot and lets the user click to set the
//  click target (x, y). Draws a crosshair at the selected point and
//  emits position on click.
//

import SwiftUI
import AppKit

struct PositionPickerView: View {
    let image: NSImage
    @Binding var x: Int
    @Binding var y: Int
    @State private var imageSize: CGSize = .zero
    @State private var displayedSize: CGSize = .zero

    var body: some View {
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
                    .onTapGesture { loc in
                        guard imageSize.width > 0 else { return }
                        let scaleX = imageSize.width / fit.width
                        let scaleY = imageSize.height / fit.height
                        // loc is relative to the image frame (top-left origin
                        // in SwiftUI). Convert to image pixel coords.
                        let imgX = Int(loc.x * scaleX)
                        let imgY = Int(loc.y * scaleY)
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
        .frame(maxHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
    }

    private func aspectFitSize(_ input: CGSize, in box: CGSize) -> CGSize {
        let scale = min(box.width / input.width, box.height / input.height)
        return CGSize(width: input.width * scale, height: input.height * scale)
    }

    /// Crosshair marker drawn at the selected (x, y) in image space.
    @ViewBuilder
    private var crosshairOverlay: some View {
        if imageSize.width > 0 && imageSize.height > 0 {
            GeometryReader { geo in
                let fit = aspectFitSize(image.size, in: geo.size)
                let scaleX = fit.width / imageSize.width
                let scaleY = fit.height / imageSize.height
                let cx = CGFloat(x) * scaleX
                let cy = CGFloat(y) * scaleY
                ZStack {
                    Circle()
                        .fill(.red.opacity(0.25))
                        .frame(width: 24, height: 24)
                    Circle()
                        .stroke(.red, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    Path { p in
                        p.move(to: CGPoint(x: cx - 14, y: cy))
                        p.addLine(to: CGPoint(x: cx + 14, y: cy))
                        p.move(to: CGPoint(x: cx, y: cy - 14))
                        p.addLine(to: CGPoint(x: cx, y: cy + 14))
                    }
                    .stroke(.red, lineWidth: 1.5)
                }
                .position(x: cx, y: cy)
            }
        }
    }
}
