# 🎯 macOS OCR AutoClicker

A native macOS automation tool that watches your screen and clicks automatically when conditions are met. Built in Swift + SwiftUI for macOS 13 (Ventura) and later.

> **by Raphael BGR** · [github.com/raphaelbgr](https://github.com/raphaelbgr)
> **Status:** 🚧 In development. Phase 1 (scaffold) is being committed now.

## What it does

macOS OCR AutoClicker captures a target — any **window**, a **screen region**, or a **full display** — compares it against reference screenshots you provide, and executes click actions automatically when the screen matches.

### Three targeting modes

| Mode | Use case |
|---|---|
| **Window** | Pick any open window. Clicks and captures stay locked to that window. |
| **Region** | Draw a rectangle on screen. Works on anything visible. |
| **Full Screen** | Capture and click anywhere on a display. Multi-monitor aware. |

### Match methods

- **Visual (default)** — Apple Vision `VNGenerateImageFeaturePrintRequest` compares the current capture against your reference screenshot. Semantic, robust to minor UI shifts.
- **Pixel-exact (SSIM)** — Accelerate/vImage SSIM for power users who need pixel-precise matching.
- **OCR text** — `VNRecognizeTextRequest` triggers an action when specific text appears on screen.

## Featured use case: iPhone Mirroring

The original version of this app targeted Apple's **iPhone Mirroring** feature. That capability is preserved as a first-class preset: select "iPhone Mirroring" as your target and you unlock extra actions — **Home**, **App Switcher**, **Spotlight**, plus **Open App** / **Close App** lifecycle controls driven via AppleScript.

See [`docs/iphone-mirroring-guide.md`](docs/iphone-mirroring-guide.md) for the tutorial.

## Requirements

- **macOS 13.0** (Ventura) or later
- Two macOS permissions, granted on first launch:
  - **Screen Recording** — to capture windows and regions
  - **Accessibility** — to synthesize clicks

## Distribution

Notarized Developer ID app, distributed as a DMG via GitHub Releases. **Not on the Mac App Store** — sandboxing prohibits the screen-capture and synthetic-input this app needs. This is the standard model for automation tools on macOS (Keyboard Maestro, BetterTouchTool, Hammerspoon, etc.).

## Privacy

**The app never makes network connections.** All image matching, OCR, and click logic runs locally using Apple frameworks (Vision, Accelerate, ScreenCaptureKit, CoreGraphics). The single third-party dependency is [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) (MIT, zero transitive deps, source-audited — no networking). SSIM / template matching are implemented in-house on Accelerate rather than pulling in unauditable binary-only OpenCV wrappers.

## Development

```bash
open "macOS AutoClicker.xcodeproj"
```

Requires Xcode 15+ (developed on Xcode 26 / Swift 6.3). Bundle ID: `com.fastsoftware.mac-autoclicker`.

## Architecture

```
macOS AutoClicker/
├── App/                  # @main SwiftUI app, scene, entitlements, Info.plist
├── Models/               # ClickAction, Timeline, Project, TargetSpec, etc.
├── Engine/               # AutomationEngine, capture, recognition, click, OCR
├── UI/                   # SwiftUI views (NavigationSplitView shell)
├── Theme/                # Semantic design tokens (system-native styling)
└── Resources/            # Assets, icon
```

Native Apple frameworks only — no Python, no OpenCV. Vision + ScreenCaptureKit + Accelerate + CGEvent.

## License

MIT — see [LICENSE](LICENSE).
