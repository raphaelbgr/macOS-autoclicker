//
//  ContentView.swift
//  macOS AutoClicker
//
//  Root view. Placeholder for Phase 1 — real NavigationSplitView shell
//  arrives in Phase 4.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)

            Text("macOS AutoClicker")
                .font(.largeTitle.bold())

            Text("Phase 1 scaffold — UI coming in Phase 4.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
