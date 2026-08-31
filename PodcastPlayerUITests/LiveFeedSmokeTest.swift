import XCTest

/// Loads a real public feed over the network. Excluded from the default suite.
@MainActor
final class LiveFeedSmokeTest: XCTestCase {

    private func load(_ address: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()   // no -uiTesting: real network, real cache
        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText(address)
        app.buttons["feed.submitButton"].tap()
        return app
    }

    func testLoadsARealPublicFeed() throws {
        let app = load("https://feeds.megaphone.fm/la-cotorrisa")

        XCTAssertTrue(
            app.staticTexts["detail.title"].waitForExistence(timeout: 30),
            "The live feed did not load"
        )

        // waitForExistence is true for off-screen elements, so a real feed with
        // a long description can leave the first row below the fold.
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

    /// Every sample offered on the first screen must actually resolve, parse,
    /// and produce playable episodes. A dead or malformed sample is worse than
    /// no sample at all.
    func testEveryOfferedSampleLoads() throws {
        for address in [
            "https://feeds.megaphone.fm/la-cotorrisa",
            "https://anchor.fm/s/7a186bc/podcast/rss",
            "http://feeds.feedburner.com/GeekNights",
            "https://jovemnerd.com.br/feed-nerdcast/",
            "https://feedpress.me/9to5machappyhour",
            "http://feeds.feedburner.com/radio-canada/aujourdhuilhistoire",
        ] {
            let app = load(address)
            XCTAssertTrue(
                app.staticTexts["detail.title"].waitForExistence(timeout: 45),
                "Sample feed did not load: \(address)"
            )
            XCTAssertTrue(
                app.buttons["detail.episodeRow.0"].waitForExistence(timeout: 15),
                "Sample feed produced no playable episodes: \(address)"
            )
            app.terminate()
        }
    }
}
