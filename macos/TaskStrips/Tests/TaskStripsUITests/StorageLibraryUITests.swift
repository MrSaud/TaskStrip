import XCTest

/// Adding a file from disk needs a real open panel, which a test can't drive — so the library is
/// seeded with one file instead (see TaskStripsApp.seedLibrary), and what's checked here is
/// everything around the panel: the two ways in, and taking a seeded file onto a strip.
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
            app.staticTexts[UITestSupport.libraryFile].waitForExistence(timeout: UITestSupport.timeout),
            "the seeded file should be on the shelf"
        )
        app.buttons["Done"].click()
    }

    func testTheToolbarOpensTheLibraryToo() {
        let button = app.buttons["Storage library"]
        XCTAssertTrue(button.waitForExistence(timeout: UITestSupport.timeout), "no storage button on the toolbar")
        button.click()

        XCTAssertTrue(
            app.staticTexts[UITestSupport.libraryFile].waitForExistence(timeout: UITestSupport.timeout),
            "the toolbar button should open the same library"
        )
        app.buttons["Done"].click()
    }

    /// The point of the library: a file put there once ends up on a strip without going near the
    /// filesystem again.
    func testAFileCanBeTakenFromTheLibraryOntoAStrip() {
        app.stripRow(titled: UITestSupport.strips[0]).doubleClick()

        let addFromLibrary = app.buttons["Add from Library…"]
        XCTAssertTrue(
            addFromLibrary.waitForExistence(timeout: UITestSupport.timeout),
            "the editor's attachments section should offer the library"
        )
        addFromLibrary.click()

        let row = app.staticTexts[UITestSupport.libraryFile]
        XCTAssertTrue(row.waitForExistence(timeout: UITestSupport.timeout), "the picker never listed the seeded file")
        row.click()
        app.buttons["Add 1"].click()

        // The strip's own summary of what's attached, which only counts what it actually holds.
        XCTAssertTrue(
            app.staticTexts["1 document"].waitForExistence(timeout: UITestSupport.timeout),
            "the copied file never landed on the strip"
        )
    }
}
