import XCTest

/// Walks the app and saves a screenshot of each screen.
///
/// Excluded from the default suite. Run it by name to refresh the README
/// images, then export them from the result bundle:
///
///     xcrun xcresulttool export attachments \
///       --path <run>.xcresult --output-path ./shots
///
/// Attached by the test rather than captured externally, so each image lands
/// at exactly the right moment instead of racing the run.
@MainActor
final class ScreenshotTour: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTour() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        capture("1-feed-source")

        field.tap()
        field.typeText("https://example.test/feed.xml")
        app.buttons["feed.submitButton"].tap()

        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 15))
        capture("2-podcast-detail")

        app.buttons["detail.episodeRow.0"].tap()
        XCTAssertTrue(app.otherElements["mini.container"].waitForExistence(timeout: 15))
        capture("3-mini-player")

        app.otherElements["mini.container"].tap()
        XCTAssertTrue(app.staticTexts["player.title"].waitForExistence(timeout: 15))
        capture("4-player")

        app.swipeDown(velocity: .fast)
        AccessibilityAuditTests.openSettings(in: app)
        XCTAssertTrue(app.staticTexts["settings.feedCacheValue"].waitForExistence(timeout: 10))
        capture("5-settings")
    }
}
