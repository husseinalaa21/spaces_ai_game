import XCTest

final class LoginAppearanceUITests: XCTestCase {
    func testLoginButtonsAndPhraseNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.husseinalaa.ai")
        app.launch()
        openLogin(app)
        let spacechat = app.buttons["login.spacechat"]
        let apple = app.buttons["login.apple"]
        XCTAssertTrue(spacechat.isHittable)
        XCTAssertTrue(apple.exists)
        XCTAssertEqual(spacechat.frame.width, apple.frame.width, accuracy: 1)
        XCTAssertGreaterThanOrEqual(spacechat.frame.height, 56)
        XCTAssertGreaterThanOrEqual(apple.frame.height, 52)
        capture(app, name: "Version 4 login buttons")
        spacechat.tap()
        let type = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Type Existing Phrase")).firstMatch
        XCTAssertTrue(type.waitForExistence(timeout: 4))
        let upload = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Upload Existing Phrase")).firstMatch
        let create = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Create New Phrase")).firstMatch
        XCTAssertTrue(upload.exists)
        XCTAssertTrue(create.exists)
        XCTAssertEqual(type.frame.width, upload.frame.width, accuracy: 1)
        XCTAssertEqual(type.frame.width, create.frame.width, accuracy: 1)
        capture(app, name: "Version 4 recovery choices")
        type.tap()
        XCTAssertTrue(app.textFields["Enter your 12 to 18 word phrase"].waitForExistence(timeout: 4))
        app.buttons["Back"].tap()
        XCTAssertTrue(type.waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(spacechat.waitForExistence(timeout: 3))
    }

    func testLoginWithLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.husseinalaa.ai")
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openLogin(app)
        let spacechat = app.buttons["login.spacechat"]
        for _ in 0..<4 where !spacechat.isHittable { app.swipeUp() }
        for _ in 0..<4 where spacechat.frame.maxY > app.frame.maxY-24 { app.swipeUp() }
        XCTAssertTrue(spacechat.isHittable)
        XCTAssertLessThanOrEqual(spacechat.frame.maxY, app.frame.maxY-8)
        XCTAssertGreaterThanOrEqual(spacechat.frame.height, 56)
        XCTAssertLessThanOrEqual(spacechat.frame.width, app.frame.width-40)
        capture(app, name: "Version 4 login with large text")
        spacechat.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Type Existing Phrase")).firstMatch.waitForExistence(timeout: 4))
    }

    private func openLogin(_ app: XCUIApplication) {
        if app.buttons["login.spacechat"].waitForExistence(timeout: 5) { return }
        let login = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Log in with Spacechat")).firstMatch
        XCTAssertTrue(login.waitForExistence(timeout: 6))
        login.tap()
        XCTAssertTrue(app.buttons["login.spacechat"].waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
