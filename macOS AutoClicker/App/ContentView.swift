//
//  ContentView.swift
//  macOS AutoClicker
//
//  Root view. Phase 1+ scaffold with Liquid Glass preview. Real
//  NavigationSplitView shell arrives in Phase 4.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            // Soft ambient gradient backdrop. On macOS 26+ the glass will
            // refract this; on older macOS the material reads against it.
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color.purple.opacity(0.10),
                    Color.black.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: DesignTokens.Spacing.xl) {
                // Hero
                VStack(spacing: DesignTokens.Spacing.s) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 56, weight: .light, design: .default))
                        .foregroundStyle(.tint)
                        .modifier(PulsingSymbol())

                    Text("macOS AutoClicker")
                        .font(.largeTitle.bold())

                    Text("Native automation for any window, region, or full screen.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Status card — previews the GlassCard primitive
                GlassCard {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                        Label("Design system ready", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(DesignTokens.Status.success)
                            .font(.headline)

                        LabeledContent("Liquid Glass") {
                            Text(LiquidGlass.isAvailable ? "macOS 26 (native)" : "Material fallback")
                                .foregroundStyle(.secondary)
                        }

                        LabeledContent("Bundle") {
                            Text(Bundle.main.bundleIdentifier ?? "unknown")
                                .font(.callout.monospaced())
                                .foregroundStyle(.tertiary)
                        }

                        LabeledContent("State") {
                            Text(appState.automationRunning ? "Running" : "Idle")
                                .foregroundStyle(appState.automationRunning
                                    ? DesignTokens.Status.success
                                    : .secondary)
                        }
                    }
                }
                .frame(maxWidth: 460)

                // Button row — previews the GlassButtonStyle primitive
                HStack(spacing: DesignTokens.Spacing.m) {
                    Button {
                        appState.startAutomation()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .glassButton(tint: .green)

                    Button {
                        appState.stopAutomation()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .glassButton(tint: .red)

                    Button {
                        appState.newProject()
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                    .glassButton()
                }
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

/// Pulses the SF Symbol on macOS 14+; static on macOS 13.
private struct PulsingSymbol: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.symbolEffect(.pulse, options: .repeating)
        } else {
            content
        }
    }
}
