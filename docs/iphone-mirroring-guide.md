# Automating iPhone Mirroring with macOS AutoClicker

iPhone Mirroring is a macOS Sequoia (15.0+) feature that displays and controls your iPhone from your Mac. macOS AutoClicker can watch the iPhone Mirroring window and tap automatically — perfect for idle games, reward collection, and repetitive iOS workflows.

> **Requirements:** macOS 15.0+ for iPhone Mirroring itself. AutoClicker runs on 13+, but this guide assumes iPhone Mirroring is available on your Mac.

## Step 1 — Grant permissions

On first launch macOS AutoClicker asks for two permissions:

| Permission | Why |
|---|---|
| **Screen Recording** | Capture the iPhone Mirroring window content |
| **Accessibility** | Send synthetic taps into the window |

System Settings → Privacy & Security → add macOS AutoClicker to both lists.

## Step 2 — Select the iPhone Mirroring target

1. Open **iPhone Mirroring** on your Mac.
2. In macOS AutoClicker, create a new project.
3. Under **Target**, choose the **iPhone Mirroring** preset. This locks captures and clicks to the mirrored iPhone display and unlocks the iOS-specific actions (Home, App Switcher, Spotlight, Open/Close App).

## Step 3 — Build your action timeline

Add one action per screen state you want to automate. Each action has:

- A **reference screenshot** of the screen state (tap **Capture** while that screen is showing on your iPhone)
- A **click position** (tap on the screenshot where the button is)
- A **similarity threshold** — `0.85` for static screens, lower (`0.60–0.75`) for dynamic games
- An optional **OCR text pattern** — comma-separated; matches if *any* of the words appear on screen

### Example: a typical idle-game loop

| # | Screen | Action | Threshold |
|---|---|---|---|
| 1 | Main menu | Tap "Play" | 0.85 |
| 2 | Level select | Tap level | 0.85 |
| 3 | Reward popup | Tap "Collect" | 0.65 |
| 4 | Results screen | Tap "Continue" | 0.85 |

## Step 4 — Run

Press **Start** (or ⌘R). AutoClicker will:

1. Capture the iPhone Mirroring window several times per second
2. Compare against every action's reference screenshot
3. When the best match clears its threshold, wait the configured delay, then tap
4. Cool down briefly, then keep scanning

Watch the activity log for live match percentages. If matches are unreliable, lower the threshold or re-capture the reference under the same lighting/UI state.

## iOS-specific actions

When the iPhone Mirroring target is selected, you also get these lifecycle actions:

- **Home** — equivalent to swiping up from the bottom of the iPhone screen
- **App Switcher** — opens the iOS app switcher
- **Spotlight** — pulls down Spotlight search on the iPhone
- **Open App** — types an app name into Spotlight and launches it
- **Close App** — either via App Switcher swipe-up (force quit) or by returning to Home

These are driven via AppleScript targeting the iPhone Mirroring process, so they require **Automation** permission in addition to the two above.

## Troubleshooting

| Problem | Fix |
|---|---|
| "No iPhone Mirroring window detected" | Open iPhone Mirroring, then refresh the target list |
| Clicks don't register | Re-check Accessibility permission |
| Black capture | Re-check Screen Recording permission |
| Low match scores | Lower threshold; re-capture under the exact UI state you want to detect |
