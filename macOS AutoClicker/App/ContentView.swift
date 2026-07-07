//
//  ContentView.swift
//  macOS AutoClicker
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        MainWindow(appState: appState)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
