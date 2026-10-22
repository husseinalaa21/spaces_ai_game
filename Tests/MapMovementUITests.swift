import XCTest

/// Runs against the installed simulator app; uses the normal guest path.
final class MapMovementUITests: XCTestCase {
    func testMapPanZoomAndTeamRelease() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.husseinalaa.ai")
        app.launch()
        let collect = app.buttons["Collect team"]
        if !collect.waitForExistence(timeout: 8) {
            let guest = app.buttons["Continue without an account"]
            XCTAssertTrue(guest.waitForExistence(timeout: 5))
            if !guest.isHittable { app.swipeUp() }
            guest.tap()
        }
        XCTAssertTrue(collect.waitForExistence(timeout: 8))
        let home = app.buttons["Back to the middle"]
        home.tap()
        let start = collect.frame
        let dotStart = collect.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        dotStart.press(forDuration: 0.05, thenDragTo: dotStart.withOffset(CGVector(dx: 45, dy: -20)), withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(home.isHittable, "Dragging the team button must not open the team screen")
        assertMoved(collect, from: start, dx: 45, dy: -20)
        home.tap()
        drag(app, dx: 75, dy: 50)
        assertMoved(collect, from: start, dx: 75, dy: 50)
        let released = collect.frame
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertEqual(collect.frame.midX, released.midX, accuracy: 2, "Map must stay where the user released it")
        XCTAssertEqual(collect.frame.midY, released.midY, accuracy: 2)
        drag(app, dx: -45, dy: -30)
        assertMoved(collect, from: released, dx: -45, dy: -30)
        home.tap()
        XCTAssertEqual(collect.frame.midX, start.midX, accuracy: 2)
        XCTAssertEqual(collect.frame.midY, start.midY, accuracy: 2)
        app.buttons["Zoom in"].tap()
        XCTAssertGreaterThan(collect.frame.width, start.width)
        let zoomed = collect.frame
        drag(app, dx: 55, dy: 35)
        assertMoved(collect, from: zoomed, dx: 55, dy: 35)
        home.tap()
        app.pinch(withScale: 1.4, velocity: 1)
        let pinched = collect.frame
        XCTAssertGreaterThan(pinched.width, start.width)
        XCTAssertTrue(home.isHittable)
        drag(app, dx: -40, dy: 25)
        assertMoved(collect, from: pinched, dx: -40, dy: 25)
        home.tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Dmap after gesture regression checks"
        attachment.lifetime = .keepAlways
        add(attachment)
        collect.tap()
        let team = app.staticTexts["Your team"]
        XCTAssertTrue(team.waitForExistence(timeout: 5))
        let teamStart = team.frame
        drag(app, dx: 65, dy: 35)
        assertMoved(team, from: teamStart, dx: 65, dy: 35)
        Thread.sleep(forTimeInterval: 0.7)
        assertMoved(team, from: teamStart, dx: 65, dy: 35)
    }

    private func drag(_ app: XCUIApplication, dx: CGFloat, dy: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.67))
        let end = start.withOffset(CGVector(dx: dx, dy: dy))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons.matching(identifier: "Back to the middle").allElementsBoundByIndex.contains { $0.isHittable }, "Dragging a moving dot must not open its screen")
    }

    private func assertMoved(_ element: XCUIElement, from frame: CGRect, dx: CGFloat, dy: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(element.frame.midX - frame.midX, dx, accuracy: 6, file: file, line: line)
        XCTAssertEqual(element.frame.midY - frame.midY, dy, accuracy: 6, file: file, line: line)
    }
}
