import XCTest

/// A deliberately excluded smoke test that hits the real network.
///
/// Everything else in this target uses fixtures, so the suite stays fast and
/// deterministic. This one exists to prove the app works against a live feed,
/// and is run by hand:
///
///     xcodebuild ... -only-testing:PodcastPlayerUITests/LiveFeedSmokeTest test
@MainActor
final class LiveFeedSmokeTest: XCTestCase {

    func testLoadsARealPublicFeed() throws {
        let app = XCUIApplication()
        app.launch()   // no -uiTesting: real network, real cache

        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("https://feeds.megaphone.fm/la-cotorrisa")
        app.buttons["feed.submitButton"].tap()

        XCTAssertTrue(
            app.staticTexts["detail.title"].waitForExistence(timeout: 30),
            "The live feed did not load"
        )
        XCTAssertTrue(app.buttons["detail.episodeRow.0"].waitForExistence(timeout: 10))

        // waitForExistence is true for off-screen elements, so a real feed with
        // a long description can leave the first row below the fold and the tap
        // lands on nothing. Scroll it into view first.
        let row = app.buttons["detail.episodeRow.0"]
        var scrolls = 0
        while !row.isHittable && scrolls < 6 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(row.isHittable, "Could not bring the first episode into view")
        row.tap()

        XCTAssertTrue(
            app.otherElements["mini.container"].waitForExistence(timeout: 20),
            "Playback did not start from a live feed"
        )
    }
}
