import XCTest

/// The credentials list. Passwords go to an in-memory store under UI testing, and the Touch ID
/// confirmation is skipped — a prompt no test can answer would hang the runner.
final class CredentialsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [UITestSupport.launchArgument]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private func openCredentials() {
        app.openMenu("View")
        let item = app.menuItem("Credentials…", in: "View")
        XCTAssertTrue(item.waitForExistence(timeout: UITestSupport.timeout), "no Credentials item in the View menu")
        item.click()
        XCTAssertTrue(
            app.staticTexts["NO CREDENTIALS YET"].waitForExistence(timeout: UITestSupport.timeout),
            "a fresh list should say it's empty"
        )
    }

    func testTheViewMenuOpensTheCredentials() {
        openCredentials()
        app.windowButton("Done").click()
    }

    func testACredentialCanBeSavedAndComesBackInTheList() {
        openCredentials()
        app.windowButton("New Credential").click()

        let title = app.textFields["credentialTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: UITestSupport.timeout), "the editor never opened")
        title.click()
        title.typeText("Consulate portal")
        app.windowButton("Create").click()

        XCTAssertTrue(
            app.staticTexts["Consulate portal"].waitForExistence(timeout: UITestSupport.timeout),
            "the new credential never reached the list"
        )
        app.windowButton("Done").click()
    }

    /// A credential is filed under what it's for, so that field is the one thing required.
    func testAnUntitledCredentialCannotBeCreated() {
        openCredentials()
        app.windowButton("New Credential").click()

        let create = app.windowButton("Create")
        XCTAssertTrue(create.waitForExistence(timeout: UITestSupport.timeout))
        XCTAssertFalse(create.isEnabled, "Create should stay off until there's something to call it")
        app.windowButton("Cancel").click()
    }

    /// A credential with no password saved says so, rather than showing dots that hide nothing.
    func testACredentialWithNoPasswordSaysSo() {
        openCredentials()
        app.windowButton("New Credential").click()

        let title = app.textFields["credentialTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: UITestSupport.timeout))
        title.click()
        title.typeText("Just a note of a URL")
        app.windowButton("Create").click()

        XCTAssertTrue(
            app.staticTexts["no password saved"].waitForExistence(timeout: UITestSupport.timeout)
        )
        app.windowButton("Done").click()
    }
}
