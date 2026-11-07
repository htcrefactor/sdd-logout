import XCTest

final class LOGOUTUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testOnboardingPreferencesAndUnpermissionedPreflight() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-onboarding"]
        app.launch()
        let next = app.buttons["onboardingContinue"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        XCTAssertFalse(next.isEnabled, "Adult eligibility must be explicit")
        XCTAssertTrue(app.staticTexts["나를 위한\n달리기의 시작."].exists, "Korean is the default")
        app.segmentedControls["onboardingLanguage"].buttons["English"].tap()
        let consent = app.switches["adultConsent"]
        for _ in 0..<4 where !consent.isHittable { app.swipeUp() }
        XCTAssertTrue(consent.isHittable)
        consent.tap()
        next.tap()
        XCTAssertTrue(app.staticTexts["What brings you outside?"].waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.staticTexts["Your coaching style"].waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.buttons["chooseRun"].waitForExistence(timeout: 5))
        app.buttons["chooseRun"].tap()
        app.buttons["workout.free"].tap()
        XCTAssertTrue(app.staticTexts["Before you go"].waitForExistence(timeout: 5))
        let start = app.buttons["startRecording"]
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.exists)
        XCTAssertFalse(start.isEnabled, "Recording requires actual location permission")
        app.buttons["Close"].tap()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["No runs in this period"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "English activity empty state"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["chooseRun"].waitForExistence(timeout: 10), "Onboarding choice survives relaunch")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["Default coach"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settingsDone"].exists)
    }
}
