//
//  AutoClickerUITests.swift
//  macOS AutoClickerUITests
//
//  XCUITest smoke suite covering the main user flows. The app honors two
//  launch arguments:
//    -uitest-reset            wipes persistence (UserDefaults + on-disk projects)
//    -uitest-skip-onboarding  marks the permission onboarding sheet as seen
//

import XCTest

final class AutoClickerUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-skip-onboarding", "-ApplePersistenceIgnoreState", "YES"]
    }

    // MARK: - a. Launch

    func testAppLaunchesAndMainWindowExists() throws {
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "Main window should exist within 10s of launch")
    }

    // MARK: - b. Onboarding sheet (launched WITHOUT the skip flag)

    func testPermissionOnboardingSheetSkipDismisses() throws {
        // Launch fresh with the onboarding overlay showing. `-uitest-onboarding-test`
        // resets persistence and forces onboarding on (leaving the flag unset even
        // though -uitest-skip-onboarding is present). This exact argument set was
        // tuned empirically for reliable window creation under XCUITest; the
        // load-bearing fix is that wipePersistence() no longer clears the NSWindow
        // restoration keys (see AppState.UITestLaunchHooks).
        app.launchArguments = [
            "-uitest-onboarding-test", "-uitest-skip-onboarding",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()

        let skipButton = app.buttons["onboardingSkipButton"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 15),
                      "Onboarding Skip button should appear on a clean launch")
        skipButton.click()

        let sheetGone = skipButton.waitForNonExistence(timeout: 5)
        XCTAssertTrue(sheetGone, "Onboarding sheet should be dismissed after Skip")
    }

    // MARK: - c. Sidebar

    func testSidebarShowsDefaultProjectRow() throws {
        app.launch()
        let row = app.buttons["sidebarProjectRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "Default 'My First Project' sidebar row should exist")
        row.click()
        // After selection the header strip shows the project name.
        XCTAssertTrue(app.staticTexts["My First Project"].firstMatch.waitForExistence(timeout: 5),
                      "Selected project name should appear in the header")
    }

    // MARK: - d. Target picker

    func testTargetPickerExposesAllOptions() throws {
        app.launch()
        let picker = app.radioGroups["targetPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10),
                      "Target picker should exist")
        // RadioGroup exposes each option as a RadioButton labeled with its title.
        let expected = ["iPhone Mirroring", "Window", "Region", "Full Screen"]
        for option in expected {
            let segment = app.radioButtons[option]
            XCTAssertTrue(segment.waitForExistence(timeout: 5),
                          "Target picker should expose option: \(option)")
        }
    }

    // MARK: - e. Add Action sheet

    func testAddActionSheetOpensAndCancels() throws {
        app.launch()
        let addBtn = app.buttons["addActionButton"].firstMatch
        XCTAssertTrue(addBtn.waitForExistence(timeout: 10),
                      "Add Action control should exist")
        addBtn.click()

        // Sheet should expose Trigger / Threshold / Delay / Reference / OCR / Click.
        XCTAssertTrue(app.staticTexts["Trigger"].waitForExistence(timeout: 5),
                      "Trigger section should be visible")
        XCTAssertTrue(app.staticTexts["Threshold"].waitForExistence(timeout: 5),
                      "Threshold field should be visible")
        XCTAssertTrue(app.staticTexts["Delay before click"].waitForExistence(timeout: 5),
                      "Delay field should be visible")
        XCTAssertTrue(app.staticTexts["Reference screenshot"].waitForExistence(timeout: 5),
                      "Reference screenshot section should be visible")
        XCTAssertTrue(app.staticTexts["Click"].waitForExistence(timeout: 5),
                      "Click section should be visible")

        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Cancel button should exist")
        cancel.click()

        let sheetClosed = app.staticTexts["Trigger"].waitForNonExistence(timeout: 5)
        XCTAssertTrue(sheetClosed, "Add Action sheet should close on Cancel")
    }

    // MARK: - f. Start/Stop control (existence only — no run)

    func testStartStopControlExistsAndIsHittable() throws {
        app.launch()
        app.activate()  // ensure the window is frontmost before probing hittability
        let startStop = app.buttons["startStopButton"]
        XCTAssertTrue(startStop.waitForExistence(timeout: 10),
                      "Start/Stop control should exist")
        // Poll for hittability: right after launch the window may not be key yet,
        // which made a bare isHittable check flaky in the full-suite run order.
        XCTAssertTrue(startStop.waitForHittable(timeout: 5),
                      "Start/Stop control should be hittable")
        // Do NOT click — would actually start the automation engine.
    }
}

// MARK: - Helpers

private extension XCUIElement {
    /// Inverse of waitForExistence: blocks up to `timeout` seconds for the
    /// element to disappear. Returns true if it became non-existent.
    @discardableResult
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if !exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return !exists
    }

    /// Blocks up to `timeout` seconds for the element to become hittable.
    /// Returns true once it is (or if it becomes so before the deadline).
    @discardableResult
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if isHittable { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return isHittable
    }
}
