import XCTest

/// Proves the app actually ships Portuguese, rather than merely containing a
/// string catalogue.
///
/// Launched with `-AppleLanguages (pt-BR)`, which is how the system chooses a
/// localization — so this exercises the same lookup a Brazilian user's device
/// would perform.
@MainActor
final class LocalizationUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        app.launch()
        return app
    }

    func testChromeIsTranslatedIntoPortuguese() {
        let app = launch(language: "pt-BR", locale: "pt_BR")

        XCTAssertTrue(
            app.staticTexts["Adicionar um podcast"].waitForExistence(timeout: 25),
            "The feed source screen is not translated"
        )
        XCTAssertTrue(app.staticTexts["Experimente um destes"].exists)

        // Tab titles come from the same catalogue. Querying a display string
        // is the point here — this suite exists to check exactly that.
        XCTAssertTrue(app.buttons["Explorar"].firstMatch.exists, "Browse tab is not translated")
    }

    func testErrorMessagesAreTranslated() {
        let app = launch(language: "pt-BR", locale: "pt_BR")

        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 25))
        field.tap()
        field.typeText("nao e um endereco")
        app.buttons["feed.submitButton"].tap()

        // AppError returns plain Strings, so it only translates if the domain
        // layer routes them through the catalogue — this is what proves it.
        XCTAssertTrue(
            app.staticTexts["Esse endereço não parece válido"].waitForExistence(timeout: 20),
            "Domain error messages are not translated"
        )
    }

    func testPluralisedCountsUsePortugueseRules() {
        let app = launch(language: "pt-BR", locale: "pt_BR")

        let field = app.textFields["feed.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 25))
        field.tap()
        field.typeText("https://example.test/feed.xml")
        app.buttons["feed.submitButton"].tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 25))

        // The fixture feed has two episodes, so this exercises the plural form.
        XCTAssertTrue(
            app.staticTexts["2 episódios"].exists,
            "Episode count is not pluralised in Portuguese"
        )
    }

    func testSettingsIsTranslated() {
        let app = launch(language: "pt-BR", locale: "pt_BR")
        XCTAssertTrue(app.textFields["feed.urlField"].waitForExistence(timeout: 25))

        AccessibilityAuditTests.openSettings(in: app, titled: "Ajustes")

        XCTAssertTrue(
            app.staticTexts["Endereços recentes"].waitForExistence(timeout: 20),
            "Settings is not translated"
        )
        XCTAssertTrue(app.staticTexts["Imagens"].exists)
    }
}
