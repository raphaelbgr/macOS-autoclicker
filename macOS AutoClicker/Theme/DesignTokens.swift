//
//  DesignTokens.swift
//  macOS AutoClicker
//
//  Semantic colors used across the app. Everything resolves against the
//  system palette so we get light/dark/vibrant/contrast for free.
//

import SwiftUI

enum DesignTokens {
    // Status colors. These stay constant across themes; semantic meaning.
    enum Status {
        static let success = Color.green
        static let warning = Color.orange
        static let error   = Color.red
        static let info    = Color.accentColor
    }

    // Log category colors — mirrors the Python app's CATEGORY_COLORS.
    enum Log {
        static let match    = Color.green
        static let mismatch = Color.gray
        static let click    = Color.cyan
        static let start    = Color.green
        static let stop     = Color.orange
        static let state    = Color.purple
        static let error    = Color.red
        static let warning  = Color.yellow
        static let info     = Color.secondary
    }

    // Surface corner radii — used consistently for visual rhythm.
    enum Radius {
        static let small:  CGFloat = 8
        static let medium: CGFloat = 12
        static let large:  CGFloat = 16
        static let xl:     CGFloat = 22
    }

    // Spacing scale.
    enum Spacing {
        static let xs: CGFloat = 4
        static let s:  CGFloat = 8
        static let m:  CGFloat = 12
        static let l:  CGFloat = 16
        static let xl: CGFloat = 24
    }
}
