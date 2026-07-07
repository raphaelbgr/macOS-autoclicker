//
//  ContentView.swift
//  macOS AutoClicker
//
//  Root content. Hosts MainWindow. Kept as a thin wrapper so the
//  @main App scene can wire AppState + window sizing in one place.
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
