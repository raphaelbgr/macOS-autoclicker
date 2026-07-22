# 🎯 macOS OCR AutoClicker

A native macOS automation tool that watches your screen and clicks automatically when conditions are met. Built in Swift + SwiftUI for macOS 13 (Ventura) and later.

> **by Raphael BGR** · [github.com/raphaelbgr](https://github.com/raphaelbgr)

## What it does

macOS OCR AutoClicker captures a target — any **window**, a **screen region**, or a **full display** — compares it against reference screenshots you provide, and executes click actions automatically when the screen matches.

### Three targeting modes

| Mode | Use case |
|---|---|
| **Window** | Pick any open window. Clicks and captures stay locked to that window. |
| **Region** | Draw a rectangle on screen. Works on anything visible. |
| **Full Screen** | Capture and click anywhere on a display. Multi-monitor aware. |

### Match methods

- **Pixel-exact SSIM (default)** — Accelerate/vImage structural similarity, the same algorithm the original Python app used (scikit-image), so imported projects and their thresholds behave identically.
- **Visual (featurePrint)** — Apple Vision `VNGenerateImageFeaturePrintRequest`. Semantic, robust to minor UI shifts; switchable per project.
- **OCR text** — `VNRecognizeTextRequest` triggers an action when specific text appears on screen. The editor OCR-scans each reference and offers the detected strings as one-click chips.

### Actions

Nine mouse gestures — **Click, Double, Triple, Right, Middle click, Long press, Drag (start → end), Scroll up / down** — all posted as real `CGEvent`s, plus the iPhone-Mirroring-only **Open app / Close app** commands. Actions fire on screen match or **chained after another action** (with per-action delay); chains cascade with cycle protection.

### Live feedback

The right-hand pane shows the live capture (~1 fps) with a **red reticle ripple marking the exact clicked spot** of each fired action, a transient "Fired: … at (x, y)" caption, and a color-coded activity log. The timeline offers a **Sort by activity** switch that floats the most recently fired action to the top with a fade highlight. Full-screen and region captures **exclude the app's own windows**, so the UI never pollutes references or matching. Every control in the app has an explanatory hover tooltip.

## Featured use case: iPhone Mirroring

The original version of this app targeted Apple's **iPhone Mirroring** feature. That capability is preserved as a first-class preset: select "iPhone Mirroring" as your target and you unlock extra actions — **Home**, **App Switcher**, **Spotlight**, plus **Open App** / **Close App** lifecycle controls driven via AppleScript.

See [`docs/iphone-mirroring-guide.md`](docs/iphone-mirroring-guide.md) for the tutorial.

## Requirements

- **macOS 13.0** (Ventura) or later
- Two macOS permissions, granted on first launch:
  - **Screen Recording** — to capture windows and regions (takes effect after an app restart — the onboarding offers Quit & Reopen)
  - **Accessibility** — to synthesize clicks (detected live, within ~2s of granting)

The onboarding screen polls the real grant state every 2 seconds, shows the app's exact bundle path with Reveal/Copy buttons for the manual "+" add flow, and explains the off-and-on re-authorize step for grants that go stale after an update. See [`docs/permissions-and-signing.md`](docs/permissions-and-signing.md) for the details and gotchas.

## Distribution

Notarized Developer ID app, distributed as a DMG via GitHub Releases. **Not on the Mac App Store** — sandboxing prohibits the screen-capture and synthetic-input this app needs. This is the standard model for automation tools on macOS (Keyboard Maestro, BetterTouchTool, Hammerspoon, etc.).

## Privacy

**The app never makes network connections.** All image matching, OCR, and click logic runs locally using Apple frameworks (Vision, Accelerate, ScreenCaptureKit, CoreGraphics). The single third-party dependency is [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) (MIT, zero transitive deps, source-audited — no networking). SSIM / template matching are implemented in-house on Accelerate rather than pulling in unauditable binary-only OpenCV wrappers.

## Development

```bash
open "macOS AutoClicker.xcodeproj"
```

Requires Xcode 15+ (developed on Xcode 26 / Swift 6.3). Bundle ID: `com.fastsoftware.mac-autoclicker`.

### Build from the command line

```bash
./scripts/build.sh           # Release build → dist/macOS AutoClicker.app
./scripts/make-dmg.sh        # Pack into dist/macOS AutoClicker.dmg
```

### UI tests

Two XCUITest suites (15 tests): a smoke suite covering the main flows and a combination suite asserting the action editor's conditional UI across the full trigger × action matrix.

```bash
xcodebuild -project "macOS AutoClicker.xcodeproj" -scheme "macOS AutoClicker" \
  -destination 'platform=macOS' test
```

macOS gates UI automation behind an interactive authorization that re-locks periodically: if the run fails with "Timed out while enabling automation mode", run the tests once from Xcode (⌘U) and authenticate, then CLI runs work. See [`docs/testing.md`](docs/testing.md). **Warning:** the suites launch with `-uitest-reset`, which wipes the app's project store — back up `~/Library/Application Support/macOS-autoclicker/projects/` first.

### Distribution (notarized DMG)

For a Gatekeeper-clean release, sign with a Developer ID Application certificate and submit to Apple's notary service:

```bash
export MAC_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="ABCDE12345"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # app-specific password
./scripts/build.sh
./scripts/sign-notarize.sh   # codesign + notarytool + staple
./scripts/make-dmg.sh
```

Tag pushes (`git tag v0.1.0 && git push origin v0.1.0`) trigger [.github/workflows/release.yml](.github/workflows/release.yml), which runs the same pipeline on GitHub-hosted macOS runners and publishes a draft GitHub Release with the DMG attached.

### CI secrets (set under Settings → Secrets → Actions)

| Secret | Purpose |
|---|---|
| `APPLE_DEVID_CERT_BASE64` | Developer ID Application `.p12`, base64-encoded |
| `APPLE_DEVID_CERT_PASSWORD` | Password for the `.p12` |
| `MAC_SIGNING_IDENTITY` | `codesign --sign` identity string |
| `APPLE_ID` / `APPLE_TEAM_ID` / `APPLE_APP_PASSWORD` | `notarytool` credentials |

If these aren't set, the workflow produces an unsigned dev build instead.

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
