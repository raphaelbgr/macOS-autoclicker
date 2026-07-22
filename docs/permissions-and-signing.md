# Permissions & Signing — how it works and every gotcha we hit

This app needs two macOS TCC permissions (TCC = the Transparency, Consent & Control
database behind System Settings → Privacy & Security):

| Permission | Used for | Detection | Takes effect |
|---|---|---|---|
| **Screen Recording** | Window/region/display capture (`ScreenCaptureKit`, `CGWindowList`) | `CGPreflightScreenCaptureAccess()` — non-prompting | **Only on a fresh launch.** macOS caches it per-process; the onboarding offers a Quit & Reopen button. |
| **Accessibility** | Posting synthetic clicks/gestures (`CGEvent`) | `AXIsProcessTrusted()` — non-prompting, updates live | Immediately (~2 s poll). |

## In-app onboarding behavior

- Polls the **live** grant state every 2 s (and on app re-activation) — no cached values.
- If either permission is missing, the onboarding overlay re-surfaces automatically.
- Shows the app's **exact bundle path** with Reveal-in-Finder / Copy Path buttons and
  numbered steps for the manual add: System Settings list → **+** → **⌘⇧G** → paste →
  Open → switch ON.
- Explains the **re-authorize** recovery: macOS binds a grant to the app's code
  signature; after an update the switch can read "on" while the current build is
  still denied — toggle it OFF and back ON.

## Gotchas (all hit during development — verified, not theoretical)

1. **Never "check" Screen Recording by capturing.** Probing with
   `CGWindowListCreateImage` re-fires the "wants to record your screen" dialog on
   every call under macOS 14+. Use `CGPreflightScreenCaptureAccess()`.
2. **Ad-hoc-signed dev builds lose their grants on every rebuild.** An ad-hoc
   signature's only identity is the build's code hash (CDHash), and TCC pins the
   grant to it — each rebuild voids the grant, forcing the off/on dance. Fix: the
   Debug config sets `DEVELOPMENT_TEAM` so local builds sign with a stable Apple
   Development identity; grants then survive rebuilds. (Shipped Developer ID builds
   always had a stable identity — end users grant once.)
3. **Keep exactly one copy of the app on disk.** With several same-bundle-id copies
   (dist/, build/, DerivedData, /Applications), macOS's "Quit & Reopen" prompt may
   relaunch a stale copy, and Accessibility grants land on the wrong binary. Install
   to `/Applications` and delete build copies.
4. **`ScreenCaptureKit` screenshots are point-size by default.** With a default
   `SCStreamConfiguration`, `SCScreenshotManager` returns a downscaled (point-size)
   frame — e.g. 1920×1080 on a 2× display whose real pixels are 3840×2160. All
   stored references and action coordinates in this app are **native pixels**, so
   every SCK capture sets `config.width/height = contentRect × pointPixelScale`.
5. **Coordinate convention:** action `x/y` are in **capture-image pixel space**
   (what the position picker writes and the matcher compares). The preview marker
   maps them picture-relative; keep any new capture path at native pixel scale or
   positions will drift by the display's scale factor.
6. **Full-screen/region captures exclude the app's own windows** (SCK
   `excludingApplications` on 14+, PID-filtered `CGWindowList` array compositing on
   13) so the app's UI can't pollute references or live matching.

## Signing & distribution

- **Debug (local dev):** `DEVELOPMENT_TEAM` on the Debug config → stable Apple
  Development signing (see gotcha 2). CLI builds that can't use Xcode's automatic
  signing can build ad-hoc and re-sign:
  `codesign --force --deep --options runtime --entitlements "macOS AutoClicker/App/MacOSAutoClicker.entitlements" --sign "Apple Development: …" <app>`
- **Release:** Developer ID + notarization via `scripts/sign-notarize.sh` (locally)
  or the tag-triggered GitHub workflow.
- **Mac App Store / TestFlight: not possible.** App Store Connect validation hard-
  requires App Sandbox, and the sandbox prohibits the synthetic input + arbitrary
  window capture this app exists for. Notarized DMG is the distribution model
  (same as Keyboard Maestro, BetterTouchTool, Hammerspoon).
