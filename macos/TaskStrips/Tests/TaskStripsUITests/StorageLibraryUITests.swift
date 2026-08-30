import XCTest

/// Adding a file needs a real open panel, which a test can't drive — so what's checked here is
/// everything around it: the two ways in, and that an empty library says so rather than looking
/// broken.
final class StorageLibraryUITests: XCTestCase {
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

    func testTheViewMenuOpensTheLibrary() {
        app.openMenu("View")
        let item = app.menuItem("Storage Library…", in: "View")
        XCTAssertTrue(item.waitForExistence(timeout: UITestSupport.timeout), "no Storage Library item in the View menu")
        item.click()

        XCTAssertTrue(
            app.staticTexts["NOTHING IN STORAGE YET"].waitForExistence(timeout: UITestSupport.timeout),
            "a fresh library should say it's empty"
        )
        app.buttons["Done"].click()
    }

    func testTheToolbarOpensTheLibraryToo() {
        let button = app.buttons["Storage library"]
        XCTAssertTrue(button.waitForExistence(timeout: UITestSupport.timeout), "no storage button on the toolbar")
        button.click()

        XCTAssertTrue(
            app.staticTexts["NOTHING IN STORAGE YET"].waitForExistence(timeout: UITestSupport.timeout),
            "the toolbar button should open the same library"
        )
        app.buttons["Done"].click()
    }
}
