import XCTest

final class TranslationUITests: XCTestCase {
    @MainActor
    func testProviderSetupAndPrivacyLink() {
        let app = XCUIApplication()
        app.launchArguments = ["-ios.interface", "en", "-ios.provider", "groq"]
        app.launch()

        XCTAssertTrue(app.buttons["translation-settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add your API key in Settings."].exists)
        app.buttons["translation-settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["API key"].exists)
        if #available(iOS 18.4, *) {
            XCTAssertTrue(app.buttons["Open Default Apps"].exists)
        }
        let privacyLink = app.descendants(matching: .any)["privacy-policy"].firstMatch
        if !privacyLink.isHittable { app.swipeUp() }
        XCTAssertTrue(privacyLink.exists)
        XCTAssertTrue(privacyLink.isHittable)
        let support = app.descendants(matching: .any)["support-developer"].firstMatch
        if !support.isHittable { app.swipeUp() }
        XCTAssertTrue(support.isHittable)
        XCTAssertEqual(support.label, "Buy the developer a coffee")
    }

    @MainActor
    func testWritingReturnsTextToCopyOrShare() throws {
        guard let server = ProcessInfo.processInfo.environment["DEEPL_TEST_SERVER"],
              URLComponents(string: server)?.host != nil else {
            throw XCTSkip("Set DEEPL_TEST_SERVER to the local QA provider.")
        }
        let app = XCUIApplication()
        app.launchArguments = [
            "-ios.interface", "en", "-ios.provider", "custom", "-ios.baseURL", server,
            "-ios.model", "test"
        ]
        app.launch()

        let writing = app.buttons["translation-write"]
        XCTAssertTrue(writing.waitForExistence(timeout: 5))
        writing.tap()
        let source = app.textViews["write-editor"]
        let action = app.buttons["write-improve"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertFalse(action.isEnabled)
        source.tap()
        source.typeText("Good mornng.")
        action.tap()
        XCTAssertTrue(app.staticTexts["Good morning."].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["Copy"].exists)
        XCTAssertTrue(app.buttons["write-share"].exists)
    }

    @MainActor
    func testTranslationAndCancellation() throws {
        guard let server = ProcessInfo.processInfo.environment["DEEPL_TEST_SERVER"],
              URLComponents(string: server)?.host != nil else {
            throw XCTSkip("Set DEEPL_TEST_SERVER to the local QA provider.")
        }
        let app = XCUIApplication()
        app.launchArguments = [
            "-ios.interface", "en", "-ios.provider", "custom", "-ios.baseURL", server,
            "-ios.model", "test", "-ios.source", "auto", "-ios.target", "en", "-ios.keepHistory", "YES"
        ]
        app.launch()

        let source = app.textViews["source-editor"]
        let action = app.buttons["start-or-stop-translation"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        source.typeText("Bonjour.")
        action.tap()
        XCTAssertTrue(app.staticTexts["Good morning."].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["Copy"].exists)
        XCTAssertTrue(app.buttons["Share"].exists)
        app.buttons["Copy"].tap()

        app.buttons["translation-history"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        let entry = app.staticTexts["Good morning."].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "history-entry").firstMatch.tap()
        XCTAssertTrue(app.buttons["Copy translation"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["History"].firstMatch.tap()
        app.buttons["Done"].tap()

        app.swipeDown()
        app.buttons["Clear"].tap()
        source.tap()
        source.typeText("Attendez.")
        action.tap()
        let stopping = NSPredicate(format: "label == %@", "Stop")
        expectation(for: stopping, evaluatedWith: action)
        waitForExpectations(timeout: 5)
        action.tap()
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.label, "Translate now")
        XCTAssertFalse(app.staticTexts["Please wait."].exists)
    }
}
