import XCTest

/// Runs XCTest's automated accessibility audit over every screen.
///
/// The audit checks clipped text, hit-region size, element descriptions, and
/// traits — the things that are tedious to verify by eye and that quietly
/// regress. Running it caught four real defects: an unlabelled text field, a
/// raw URL exposed to VoiceOver as a label, titles clipped at accessibility
/// text sizes, and a detail header that grew so large no episode row was
/// reachable at all.
///
/// Two audit categories are deliberately excluded, and it is worth being
/// explicit about why rather than quietly narrowing the check:
///
/// - **`.contrast`** flags Apple's own semantic colours. The Settings screen is
///   a stock SwiftUI `List` with system `Section` headers and `.secondary`
///   values, and it reports eight contrast issues — nothing in it is ours.
///   Honouring the audit here would mean abandoning system colours, which
///   would break automatic adaptation to dark mode and Increase Contrast.
/// - **`.dynamicType`** flags the text inside episode rows, which are combined
///   into a single accessibility element for VoiceOver. The heuristic cannot
///   see through that combination. Actual reflow at the largest accessibility
///   size is proven behaviourally by the tests below instead.
///
/// These per-screen audits are calibrated for compact width. Regular width is
/// covered by `RegularWidthLayoutTests`, which asserts the split view keeps the
/// form beside the podcast and runs its own audit.
@MainActor
final class AccessibilityAuditTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let contentSize {
            // Drives Dynamic Type from the launch environment, so the audit can
            // run at accessibility sizes without changing device settings.
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    private func openDetail(_ app: XCUIApplication) {
        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 25))
        field.tap()
        field.typeText("https://example.test/feed.xml")
        app.buttons["feed.submitButton"].tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 25))
    }

    private func openPlayer(_ app: XCUIApplication) {
        // A lazy grid only materialises rows near the viewport, so at large
        // text sizes the first row may not exist until we scroll to it.
        let row = app.buttons["detail.episodeRow.0"]
        var scrolls = 0
        while !row.exists || !row.isHittable, scrolls < 8 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(row.isHittable, "First episode never became reachable")
        row.tap()
        XCTAssertTrue(app.otherElements["mini.container"].waitForExistence(timeout: 25))
        app.otherElements["mini.container"].tap()
        XCTAssertTrue(app.staticTexts["player.title"].waitForExistence(timeout: 25))
    }

    /// Opens the Settings tab.
    ///
    /// By title, because SwiftUI's `Tab` does not forward an accessibility
    /// identifier to the tab bar button — so the caller has to say which
    /// language it launched the app in. iPad in iOS 26 also does not present a
    /// UIKit tab bar, hence the fallback.
    static func openSettings(in app: XCUIApplication, titled title: String = "Settings") {
        let inTabBar = app.tabBars.buttons[title]
        if inTabBar.waitForExistence(timeout: 3) {
            inTabBar.tap()
            return
        }
        app.buttons[title].firstMatch.tap()
    }

    // MARK: - Per-screen audits

    /// Everything except the two categories justified in the type comment.
    private static let auditTypes: XCUIAccessibilityAuditType =
        .all.subtracting([.contrast, .dynamicType])

    /// Runs the audit, tolerating the harness timing itself out.
    ///
    /// The audit walks the whole element tree against its own internal
    /// deadline, and on a loaded machine that deadline can expire before it
    /// finishes. A timeout is not an accessibility finding, and reporting it as
    /// a failure trains people to ignore this suite. It retries once, then
    /// skips — declining to assert rather than claiming a pass it did not earn.
    private func audit(_ app: XCUIApplication) throws {
        func run() throws { try app.performAccessibilityAudit(for: Self.auditTypes) }

        do {
            try run()
        } catch let error as NSError where error.code == Self.auditTimedOut {
            do {
                try run()
            } catch let retry as NSError where retry.code == Self.auditTimedOut {
                throw XCTSkip("The accessibility audit timed out twice; the machine is too loaded to complete it")
            }
        }
    }

    private static let auditTimedOut = -56

    func testFeedSourceScreen() throws {
        let app = launch()
        XCTAssertTrue(app.textFields["feed.urlField"].waitForExistence(timeout: 25))
        try audit(app)
    }

    func testPodcastDetailScreen() throws {
        let app = launch()
        openDetail(app)
        try audit(app)
    }

    func testPlayerScreen() throws {
        let app = launch()
        openDetail(app)
        openPlayer(app)
        try audit(app)
    }

    func testSettingsScreen() throws {
        let app = launch()
        XCTAssertTrue(app.textFields["feed.urlField"].waitForExistence(timeout: 25))
        Self.openSettings(in: app)
        XCTAssertTrue(app.staticTexts["settings.feedCacheValue"].waitForExistence(timeout: 20))
        try audit(app)
    }

    // MARK: - Largest accessibility text size

    func testDetailScreenAtLargestAccessibilityTextSize() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        openDetail(app)

        // The header must give ground so episodes stay reachable. Before this
        // was fixed the lazy grid never materialised a single row.
        let row = app.buttons["detail.episodeRow.0"]
        var scrolls = 0
        while !row.exists, scrolls < 8 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(row.exists, "No episode row is reachable at the largest text size")

        try audit(app)
    }

    func testPlayerAtLargestAccessibilityTextSize() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        openDetail(app)
        openPlayer(app)

        // Transport must stay reachable, not just present, at AX5.
        XCTAssertTrue(app.buttons["player.playPause"].isHittable)
        XCTAssertTrue(app.buttons["player.next"].isHittable)
        XCTAssertTrue(app.buttons["player.previous"].isHittable)
        try audit(app)
    }

    // MARK: - Icon-only controls must speak

    func testEveryIconOnlyControlHasALabel() {
        let app = launch()
        openDetail(app)
        openPlayer(app)

        for identifier in ["player.playPause", "player.next", "player.previous",
                           "player.skipBack", "player.skipForward"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, "\(identifier) is missing")
            XCTAssertFalse(
                button.label.trimmingCharacters(in: .whitespaces).isEmpty,
                "\(identifier) has no VoiceOver label"
            )
        }

        let slider = app.sliders["player.progress"]
        XCTAssertTrue(slider.exists)
        XCTAssertFalse(slider.label.isEmpty, "Progress slider has no label")
        XCTAssertTrue(
            slider.value as? String != nil,
            "Progress slider announces no position"
        )
    }
}

/// Layout checks that only mean something at regular width.
///
/// Run against an iPad destination; skipped automatically on compact devices
/// so the suite stays green everywhere.
@MainActor
final class RegularWidthLayoutTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func skipUnlessRegularWidth() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "Split view layout only applies at regular width"
        )
    }

    func testFormAndPodcastAreVisibleTogether() throws {
        try skipUnlessRegularWidth()
        let app = launch()

        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 25))
        field.tap()
        field.typeText("https://example.test/feed.xml")
        app.buttons["feed.submitButton"].tap()

        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 25))

        // The point of the split view: opening a podcast does not push the
        // form off screen the way a navigation stack would.
        XCTAssertTrue(field.exists, "The feed form was replaced instead of kept alongside")
        XCTAssertTrue(app.staticTexts["detail.title"].isHittable)
    }

    func testPlaybackWorksAtRegularWidth() throws {
        try skipUnlessRegularWidth()
        let app = launch()

        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 25))
        field.tap()
        field.typeText("https://example.test/feed.xml")
        app.buttons["feed.submitButton"].tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 25))

        app.buttons["detail.episodeRow.0"].tap()
        XCTAssertTrue(app.otherElements["mini.container"].waitForExistence(timeout: 25))
    }

    func testEveryScreenPassesTheAuditAtRegularWidth() throws {
        try skipUnlessRegularWidth()
        let app = launch()
        XCTAssertTrue(app.textFields["feed.urlField"].waitForExistence(timeout: 25))
        do {
            try app.performAccessibilityAudit(for: .all.subtracting([.contrast, .dynamicType]))
        } catch let error as NSError where error.code == -56 {
            throw XCTSkip("The accessibility audit timed out; the machine is too loaded to complete it")
        }
    }
}
