# UI testing — running the XCUITest suites

Target `macOS AutoClickerUITests`, shared scheme `macOS AutoClicker`. Two suites, 15 tests:

- **`AutoClickerUITests`** — 6 smoke tests: launch/window, onboarding Skip flow,
  sidebar selection, target picker options, Add-Action sheet fields, Start/Stop.
- **`ActionEditorCombinationTests`** — 9 tests asserting the editor's conditional UI
  over the trigger × action matrix (recognition vs after-trigger; every gesture's
  special fields; Open/Close-app sections; the phone-only warning).

## Run

```bash
xcodebuild -project "macOS AutoClicker.xcodeproj" -scheme "macOS AutoClicker" \
  -destination 'platform=macOS' test
```

## The automation-mode gate (read this when the run fails)

macOS gates UI-test automation behind an **interactive authorization**
(`testmanagerd` requires Touch ID / password to enable automation mode). It
**re-locks periodically** (observed: daily). Symptom:

```
Failed to initialize for UI testing: … Timed out while enabling automation mode.
```

Fix: run the tests once from Xcode (**⌘U**) and authenticate the dialog; CLI runs
then work until the next re-lock. No headless workaround exists.

## Launch-argument hooks (app side)

| Argument | Effect |
|---|---|
| `-uitest-reset` | Wipes the onboarding flag + the app-support project store, so tests start deterministic |
| `-uitest-skip-onboarding` | Marks onboarding as completed (suppresses the overlay) |
| `-uitest-onboarding-test` | Reset + force the onboarding overlay to show (used by the onboarding test) |
| `-ApplePersistenceIgnoreState YES` | Skips macOS window-state restoration — without it the SwiftUI window can fail to appear under XCUITest |

## Hard-learned constraints

1. **`-uitest-reset` deletes the REAL user project store**
   (`~/Library/Application Support/macOS-autoclicker/projects/`). There is no test
   isolation yet — back up that directory before running the suites on a machine
   with real projects. (Improvement backlog: point the test store at a temp dir.)
2. **Window restoration:** the original all-6-failures run traced to macOS
   restoring zero windows after XCUITest's SIGKILL relaunch cycle; the fix is the
   `-ApplePersistenceIgnoreState YES` argument plus `wipePersistence()` clearing
   only app keys (never `removePersistentDomain`, which nukes the NSWindow
   restoration keys SwiftUI needs).
3. **Permission gate ≠ automation gate.** The app's Screen-Recording/Accessibility
   permissions and the test runner's automation-mode authorization are independent;
   the 2-second permission-gate poll is suppressed under any `-uitest*` argument so
   tests stay deterministic.
4. A connected iPhone can spam `xcodebuild` output with unrelated
   `DTDKRemoteDeviceConnection` errors — filter with
   `grep -Ev "DTDK|iPhoneConnect|Developer Disk Image"`; they are not failures.
