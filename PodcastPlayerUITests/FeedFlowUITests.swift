import XCTest

/// End-to-end flows against fixture data.
///
/// Launched with `-uiTesting`, which swaps in an in-memory store and a fixture
/// HTTP client — so these exercise the real parse, cache, and render path with
/// no network and no state inherited from a previous run.
@MainActor
final class FeedFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        // These tests query display strings, so the language is pinned rather
        // than inherited from whatever the simulator happens to be set to.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func loadFeed(in app: XCUIApplication) {
        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "URL field never appeared")
        field.tap()
        field.typeText("https://example.test/feed.xml")
        app.buttons["feed.submitButton"].tap()
    }

    func testLoadingAFeedShowsItsEpisodes() {
        let app = launch()
        loadFeed(in: app)

        XCTAssertTrue(
            app.staticTexts["detail.title"].waitForExistence(timeout: 20),
            "Detail screen never appeared"
        )
        XCTAssertEqual(app.staticTexts["detail.title"].label, "Rich Metadata Show")
        XCTAssertTrue(app.staticTexts["detail.author"].exists)
        XCTAssertTrue(app.buttons["detail.episodeRow.0"].exists)
    }

    func testPlayingAnEpisodeShowsTheMiniPlayerAndExpands() {
        let app = launch()
        loadFeed(in: app)

        let firstEpisode = app.buttons["detail.episodeRow.0"]
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 20))
        firstEpisode.tap()

        let mini = app.otherElements["mini.container"]
        XCTAssertTrue(mini.waitForExistence(timeout: 20), "Mini player never appeared")

        let miniTitle = app.staticTexts["mini.title"].label
        mini.tap()

        let playerTitle = app.staticTexts["player.title"]
        XCTAssertTrue(playerTitle.waitForExistence(timeout: 20), "Full player never appeared")
        XCTAssertEqual(playerTitle.label, miniTitle, "Player and mini player disagree on what is playing")

        // The sheet animates in, so these wait rather than checking bare
        // existence the instant the title appears.
        XCTAssertTrue(app.buttons["player.playPause"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["player.next"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["player.previous"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.sliders["player.progress"].waitForExistence(timeout: 20))
    }

    func testAnInvalidAddressShowsAnActionableError() {
        let app = launch()

        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText("not a url")
        app.buttons["feed.submitButton"].tap()

        XCTAssertTrue(
            app.staticTexts["state.errorTitle"].waitForExistence(timeout: 5),
            "No error shown for an unusable address"
        )
        // Retrying a mistyped address fails identically every time, so no
        // Retry button should be offered.
        XCTAssertFalse(app.buttons["state.retry"].exists)
    }

    func testTheClearButtonEmptiesTheFieldAndDismissesAnyError() {
        let app = launch()

        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))

        // Absent until there is something to clear.
        XCTAssertFalse(app.buttons["feed.clearField"].exists)

        field.tap()
        field.typeText("not a url")

        let clear = app.buttons["feed.clearField"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3), "Clear button never appeared")

        app.buttons["feed.submitButton"].tap()
        XCTAssertTrue(app.staticTexts["state.errorTitle"].waitForExistence(timeout: 5))

        clear.tap()

        XCTAssertEqual(field.value as? String ?? "", "")
        XCTAssertFalse(
            app.staticTexts["state.errorTitle"].exists,
            "The error about the deleted address is still on screen"
        )
        XCTAssertFalse(app.buttons["feed.clearField"].exists)
    }

    func testTappingAwayDismissesTheKeyboard() {
        let app = launch()

        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText("example.test")

        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "Keyboard never appeared")

        // Somewhere empty, well clear of any control.
        app.staticTexts["Add a podcast"].tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.keyboards.element)
        waitForExpectations(timeout: 5)
    }

    func testClearingRecentAddressesAsksWithAnAlert() {
        let app = launch()

        // Load something so there is history to clear.
        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText("https://example.test/feed.xml")
        app.buttons["feed.submitButton"].tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 25))

        let recent = app.staticTexts["Recent"]
        if !recent.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(recent.waitForExistence(timeout: 5))
        }

        app.buttons["feed.clearHistory"].tap()

        let alert = app.alerts["Clear recent addresses?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Expected an alert, not an action sheet")
        XCTAssertTrue(alert.buttons["Cancel"].exists, "A destructive alert must offer a way out")

        // Cancelling leaves the history alone.
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(recent.exists)

        app.buttons["feed.clearHistory"].tap()
        app.alerts["Clear recent addresses?"].buttons["Clear"].tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: recent)
        waitForExpectations(timeout: 5)
    }

    func testEverySampleFeedIsOffered() {
        let app = launch()
        XCTAssertTrue(app.textFields["feed.urlField"].waitForExistence(timeout: 20))

        for name in ["La Cotorrisa", "Instituto Claro", "Geek Nights",
                     "NerdCast", "9to5Mac Happy Hour", "Aujourd'hui l'histoire"] {
            XCTAssertTrue(
                app.buttons["feed.sample.\(name)"].exists,
                "Sample feed \(name) is missing"
            )
        }
    }

    func testASuccessfulLoadIsRememberedInHistory() {
        let app = launch()
        loadFeed(in: app)

        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 20))

        // At regular width the form stays on screen beside the podcast, so
        // there is nothing to navigate back from.
        let recent = app.staticTexts["Recent"]
        if !recent.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        XCTAssertTrue(
            recent.waitForExistence(timeout: 5),
            "History section never appeared after a successful load"
        )
    }
}

@MainActor
final class CacheUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testSettingsReportsAndClearsTheCaches() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // Load a feed so there is something to clear.
        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText("https://example.test/feed.xml")
        app.buttons["feed.submitButton"].tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 20))

        AccessibilityAuditTests.openSettings(in: app)

        let feedValue = app.staticTexts["settings.feedCacheValue"]
        XCTAssertTrue(feedValue.waitForExistence(timeout: 5))
        XCTAssertEqual(feedValue.label, "1 feed")

        app.buttons["settings.clearFeeds"].tap()

        // Scoped to the alert: the row itself also has a "Clear" button, so an
        // unscoped query matches two elements and fails.
        let alert = app.alerts["Clear podcast cache?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Expected an alert, not an action sheet")
        XCTAssertTrue(alert.buttons["Cancel"].exists, "A destructive alert must offer a way out")
        alert.buttons["Clear"].tap()

        let expectation = expectation(
            for: NSPredicate(format: "label == %@", "0 feeds"),
            evaluatedWith: feedValue
        )
        wait(for: [expectation], timeout: 5)
    }
}
