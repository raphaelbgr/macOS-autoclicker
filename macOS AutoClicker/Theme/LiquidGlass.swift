//
//  LiquidGlass.swift
//  macOS AutoClicker
//
//  Liquid Glass design system with graceful degradation.
//
//  macOS 26 (Tahoe) and later → real `.glassEffect()` material.
//  macOS 13–25 → elegant `.regularMaterial` fallback so the app still
//  looks polished on older systems.
//
//  All custom glass UI in this app goes through these helpers so the
//  availability gate lives in exactly one place.
//

import SwiftUI

/// Availability flag for the Liquid Glass material system (macOS 26 / Tahoe).
enum LiquidGlass {
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

// MARK: - Glass card container

/// A floating card surface.
///
/// On macOS 26+ this renders as a real Liquid Glass panel with the given
/// shape; on earlier macOS it falls back to a vibrant regular material with
/// matching corner radius. Use this for every grouped surface in the app so
/// the visual language stays consistent across OS versions.
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let tint: Color?
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = 16,
        tint: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            content()
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(tintedGlass, in: .rect(cornerRadius: cornerRadius))
        } else {
            content()
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(fallbackBorderOpacity), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                .overlay(tintOverlay)
        }
    }

    @available(macOS 26.0, *)
    private var tintedGlass: Glass {
        if let tint { return Glass.regular.tint(tint) }
        return Glass.regular
    }

    private var fallbackBorderOpacity: Double { tint == nil ? 0.08 : 0.12 }

    @ViewBuilder
    private var tintOverlay: some View {
        if let tint {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint.opacity(0.10))
        }
    }
}

// MARK: - Glass pill button

/// A prominent control button that adapts to the system material.
///
/// On macOS 26+, button styles like `.glassProminent` are available natively;
/// we use a custom shape + `.glassEffect` so the styling is identical to the
/// rest of the app. On older macOS we emulate it with material + subtle
/// gradient + hover feedback.
struct GlassButtonStyle: ButtonStyle {
    let tint: Color?
    let glow: Bool

    init(tint: Color? = nil, glow: Bool = false) {
        self.tint = tint
        self.glow = glow
    }

    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(
            configuration: configuration,
            tint: tint,
            glow: glow
        )
    }

    private struct ButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let tint: Color?
        let glow: Bool

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .foregroundStyle(labelColor)
                .modifier(GlassButtonMaterial(tint: tint, isPressed: configuration.isPressed))
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
        }

        private var labelColor: Color {
            if tint != nil { return .white }
            return .primary
        }
    }
}

private struct GlassButtonMaterial: ViewModifier {
    let tint: Color?
    let isPressed: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(tintedGlass, in: .capsule)
        } else {
            content
                .background(
                    Capsule()
                        .fill(fallbackBackground)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: shadowColor, radius: isPressed ? 1 : 3, y: isPressed ? 0 : 2)
        }
    }

    @available(macOS 26.0, *)
    private var tintedGlass: Glass {
        if let tint { return Glass.regular.tint(tint) }
        return Glass.regular
    }

    private var fallbackBackground: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [tint.opacity(0.95), tint.opacity(0.80)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(.regularMaterial)
    }

    private var shadowColor: Color {
        if tint != nil { return (tint ?? .accentColor).opacity(0.35) }
        return .black.opacity(0.18)
    }
}

// MARK: - View extensions

extension View {
    /// Apply the app's standard glass card container to this view.
    func glassCard(
        cornerRadius: CGFloat = 16,
        tint: Color? = nil
    ) -> some View {
        GlassCard(cornerRadius: cornerRadius, tint: tint) { self }
    }

    /// Standard glass button style. Pass a tint for prominent actions.
    func glassButton(tint: Color? = nil, glow: Bool = false) -> some View {
        buttonStyle(GlassButtonStyle(tint: tint, glow: glow))
    }
}
