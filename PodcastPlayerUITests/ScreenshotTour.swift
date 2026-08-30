import XCTest

/// Walks the app slowly so screenshots can be captured for the README.
/// Excluded from the default suite; run by name when refreshing screenshots.
@MainActor
final class ScreenshotTour: XCTestCase {

    func testTour() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3)          // screen 1

        field.tap()
        field.typeText("https://example.test/feed.xml")
        app.buttons["feed.submitButton"].tap()

        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 4)          // screen 2

        app.buttons["detail.episodeRow.0"].tap()
        XCTAssertTrue(app.otherElements["mini.container"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 4)          // mini player

        app.otherElements["mini.container"].tap()
        XCTAssertTrue(app.staticTexts["player.title"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 6)          // screen 3

        app.swipeDown(velocity: .fast)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["settings.feedCacheValue"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 5)          // settings
    }
}
