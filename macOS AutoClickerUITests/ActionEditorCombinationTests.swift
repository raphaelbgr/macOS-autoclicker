//
//  ActionEditorCombinationTests.swift
//  macOS AutoClickerUITests
//
//  Combination suite for the ActionEditorSheet conditional UI. Each test drives
//  a (triggerType, actionType/clickType, openMethod) combination and asserts
//  which sections / fields are visible, matching the editor's show/hide rules.
//
//  Rules covered (spec):
//   1. Recognition trigger  -> Threshold slider, OCR field, "Reference screenshot".
//   2. After-another-action -> Threshold + OCR hidden; afterActionPicker shown
//      when the timeline has siblings; "Click position" section still shown for
//      click gestures (with Capture Now + position picker).
//   3. Nine gesture types   -> Click section (Position + Repeat count) visible;
//      Drag adds "End position"; Long press adds "Hold duration (ms)";
//      Scroll up/down show the "Scrolls 5 lines per repeat" caption.
//   4. Open app             -> Click section hidden; "Open app" section shown;
//      Spotlight -> "App name"; Tap icon -> "Tap position" + reference section.
//   5. Close app            -> Click section hidden; "Close app" Method picker.
//   6. Phone-only warning   -> shown for Open/Close app, not for gestures.
//

import XCTest

final class ActionEditorCombinationTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-skip-onboarding", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "Main window should exist within 10s of launch")
    }

    // MARK: - Rule 1 — Recognition trigger

    func testRecognitionTriggerShowsThresholdOCRAndReferenceSection() throws {
        XCTAssertTrue(openAddActionEditor(), "Add Action editor sheet should open")
        // Default trigger is "When screen matches" (recognition) and default
        // action is a single Click, so the recognition-only fields are shown.
        XCTAssertTrue(app.staticTexts["Threshold"].waitForExistence(timeout: 3),
                      "Threshold label should be visible under the recognition trigger")
        XCTAssertTrue(app.sliders.firstMatch.exists,
                      "Threshold slider should be visible under the recognition trigger")
        XCTAssertTrue(anyElement("ocrTextField").exists,
                      "OCR text field (ocrTextField) should be visible under the recognition trigger")
        XCTAssertTrue(app.staticTexts["Reference screenshot"].exists,
                      "Reference screenshot section should be visible under the recognition trigger")
    }

    // MARK: - Rule 2 — After another action

    func testAfterTriggerHidesThresholdOCRShowsPickerAndClickPosition() throws {
        // The After-action picker only lists siblings, so create one action first.
        XCTAssertTrue(openAddActionEditor(), "First editor sheet should open to seed the timeline")
        XCTAssertTrue(tapAdd(), "First (seed) action should be added via the Add button")
        XCTAssertTrue(app.staticTexts["Trigger"].waitForNonExistence(timeout: 5),
                      "Editor sheet should close after adding the seed action")

        // Open a second editor and switch the Trigger to "After another action".
        XCTAssertTrue(openAddActionEditor(), "Second editor sheet should open")
        XCTAssertTrue(choose(picker: "Type", option: "After another action"),
                      "Should be able to switch the Trigger picker to 'After another action'")

        XCTAssertFalse(app.staticTexts["Threshold"].exists,
                       "Threshold should be HIDDEN under the after-action trigger")
        XCTAssertFalse(app.sliders.firstMatch.exists,
                       "Threshold slider should be HIDDEN under the after-action trigger")
        XCTAssertFalse(anyElement("ocrTextField").exists,
                       "OCR field should be HIDDEN under the after-action trigger")

        XCTAssertTrue(anyElement("afterActionPicker").waitForExistence(timeout: 3),
                      "afterActionPicker should appear when the timeline has other actions")

        // Default action is a click gesture, so the position section stays put,
        // now titled "Click position" (recognition is off).
        XCTAssertTrue(app.staticTexts["Click position"].exists,
                      "Click position section should remain visible for a click gesture under the after-action trigger")
        XCTAssertTrue(app.buttons["Capture Now"].exists,
                      "Capture Now button should remain available in the position section")
    }

    // MARK: - Rule 3 — Gesture types

    func testClickGestureShowsPositionAndRepeatCount() throws {
        XCTAssertTrue(openAddActionEditor(), "Editor sheet should open")
        // Default Action picker value is "Click".
        XCTAssertTrue(app.staticTexts["Position"].waitForExistence(timeout: 3),
                      "Position row should be visible in the Click section")
        XCTAssertTrue(app.staticTexts["Repeat count"].exists,
                      "Repeat count row should be visible in the Click section")
    }

    func testDragGestureShowsEndPosition() throws {
        XCTAssertTrue(openAddActionEditor(), "Editor sheet should open")
        XCTAssertTrue(choose(picker: "Action", option: "Drag"),
                      "Should be able to choose Drag from the Action picker")
        XCTAssertTrue(app.staticTexts["End position"].waitForExistence(timeout: 3),
                      "Drag should additionally expose the End position row")
        XCTAssertTrue(app.staticTexts["Position"].exists,
                      "Drag should still show the Position row")
    }

    func testLongPressAndScrollGesturesShowSpecialFields() throws {
        XCTAssertTrue(openAddActionEditor(), "Editor sheet should open")

        XCTAssertTrue(choose(picker: "Action", option: "Long press"),
                      "Should be able to choose Long press")
        XCTAssertTrue(app.staticTexts["Hold duration (ms)"].waitForExistence(timeout: 3),
                      "Long press should expose the Hold duration (ms) row")

        XCTAssertTrue(choose(picker: "Action", option: "Scroll up"),
                      "Should be able to choose Scroll up")
        XCTAssertTrue(scrollLinesCaption().waitForExistence(timeout: 3),
                      "Scroll up should show the 'Scrolls 5 lines per repeat' caption")

        XCTAssertTrue(choose(picker: "Action", option: "Scroll down"),
                      "Should be able to choose Scroll down")
        XCTAssertTrue(scrollLinesCaption().exists,
                      "Scroll down should show the 'Scrolls 5 lines per repeat' caption")
    }

    // MARK: - Rule 4 — Open app

    func testOpenAppSpotlightShowsAppNameAndHidesClick() throws {
        XCTAssertTrue(openAddActionEditor(), "Editor sheet should open")
        XCTAssertTrue(choose(picker: "Action", option: "Open app (for iPhone Mirroring)"),
                      "Should be able to choose Open app")
        XCTAssertFalse(app.staticTexts["Click"].exists,
                       "Click section should be HIDDEN for an Open app action")
        XCTAssertTrue(app.staticTexts["Open app"].waitForExistence(timeout: 3),
                      "Open app section should be visible")
        // Default open method is Spotlight.
        XCTAssertTrue(app.textFields["App name"].exists,
                      "App name field should be visible under the Spotlight method")
    }

    func testOpenAppTapIconShowsTapPositionAndReferenceSection() throws {
        XCTAssertTrue(openAddActionEditor(), "Editor sheet should open")
        XCTAssertTrue(choose(picker: "Action", option: "Open app (for iPhone Mirroring)"),
                      "Should be able to choose Open app")
        XCTAssertTrue(choose(picker: "Method", option: "Tap icon (x, y)"),
                      "Should be able to switch the Open app method to Tap icon")
        XCTAssertTrue(app.staticTexts["Tap position"].waitForExistence(timeout: 3),
                      "Tap position row should be visible under the Tap icon method")
        // Reference/position section stays visible (default trigger is recognition,
        // and tap-icon also needsPosition), titled "Reference screenshot".
        XCTAssertTrue(app.staticTexts["Reference screenshot"].exists,
                      "Reference screenshot section should remain visible under the Tap icon method")
    }

    // MARK: - Rule 5 — Close app

    func testCloseAppShowsMethodPickerAndHidesClick() throws {
        XCTAssertTrue(openAddActionEditor(), "Editor sheet should open")
        XCTAssertTrue(choose(picker: "Action", option: "Close app (for iPhone Mirroring)"),
                      "Should be able to choose Close app")
        XCTAssertFalse(app.staticTexts["Click"].exists,
                       "Click section should be HIDDEN for a Close app action")
        XCTAssertTrue(app.staticTexts["Close app"].waitForExistence(timeout: 3),
                      "Close app section should be visible")
        XCTAssertTrue(app.popUpButtons["Method"].exists,
                      "Close app Method picker should be visible")
    }

    // MARK: - Rule 6 — Phone-only warning note

    func testPhoneOnlyWarningForAppActionsNotGestures() throws {
        XCTAssertTrue(openAddActionEditor(), "Editor sheet should open")

        // Default gesture (Click) -> no warning.
        XCTAssertFalse(phoneOnlyWarning().exists,
                       "Phone-only warning should NOT appear for a click gesture")

        XCTAssertTrue(choose(picker: "Action", option: "Open app (for iPhone Mirroring)"),
                      "Should be able to choose Open app")
        XCTAssertTrue(phoneOnlyWarning().waitForExistence(timeout: 3),
                      "Phone-only warning should appear for Open app")

        XCTAssertTrue(choose(picker: "Action", option: "Close app (for iPhone Mirroring)"),
                      "Should be able to choose Close app")
        XCTAssertTrue(phoneOnlyWarning().exists,
                      "Phone-only warning should appear for Close app")

        XCTAssertTrue(choose(picker: "Action", option: "Click"),
                      "Should be able to switch back to Click")
        XCTAssertFalse(phoneOnlyWarning().exists,
                       "Phone-only warning should NOT appear after switching back to a click gesture")
    }

    // MARK: - Driving helpers

    /// Open the Add Action editor via the toolbar/sidebar control and wait for
    /// the sheet's Trigger section to appear.
    @discardableResult
    private func openAddActionEditor() -> Bool {
        let addBtn = app.buttons["addActionButton"].firstMatch
        guard addBtn.waitForExistence(timeout: 10) else { return false }
        addBtn.click()
        return app.staticTexts["Trigger"].waitForExistence(timeout: 5)
    }

    /// Drive a SwiftUI Picker rendered as a macOS popup button: open it, then
    /// pick the option whose visible title matches `option`.
    @discardableResult
    private func choose(picker label: String, option title: String) -> Bool {
        let popUp = app.popUpButtons[label].firstMatch
        guard popUp.waitForExistence(timeout: 5) else { return false }
        popUp.click()
        let item = app.menuItems[title]
        guard item.waitForExistence(timeout: 5) else { return false }
        item.click()
        return true
    }

    /// Tap the primary footer button that stores a new action ("Add").
    @discardableResult
    private func tapAdd() -> Bool {
        let add = app.buttons["Add"].firstMatch
        guard add.waitForExistence(timeout: 3) else { return false }
        add.click()
        return true
    }

    /// Look up an element by accessibility identifier across any element type.
    /// Used for ids that may surface on different controls depending on how the
    /// SwiftUI view is bridged to AppKit (popUpButton vs. other).
    private func anyElement(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// The "Scrolls 5 lines per repeat …" caption. Matched by prefix to avoid
    /// depending on the em-dash glyph in the assertion string.
    private func scrollLinesCaption() -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH 'Scrolls 5 lines per repeat'")
        ).firstMatch
    }

    /// The phone-only warning Label. Matched by substring since SwiftUI Labels
    /// may collapse icon + text into a single staticText.
    private func phoneOnlyWarning() -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'Phone-only action'")
        ).firstMatch
    }
}

// MARK: - Element wait helpers (file-local)

private extension XCUIElement {
    /// Inverse of waitForExistence: blocks up to `timeout` seconds for the
    /// element to disappear. Returns true once it is gone.
    @discardableResult
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if !exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return !exists
    }
}
