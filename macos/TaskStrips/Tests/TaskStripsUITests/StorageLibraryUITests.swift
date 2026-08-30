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
        app.windowButton("Done").click()
    }

    func testTheToolbarOpensTheLibraryToo() {
        let button = app.windowButton("Storage library")
        XCTAssertTrue(button.waitForExistence(timeout: UITestSupport.timeout), "no storage button on the toolbar")
        button.click()

        XCTAssertTrue(
            app.staticTexts[UITestSupport.libraryFile].waitForExistence(timeout: UITestSupport.timeout),
            "the toolbar button should open the same library"
        )
        app.windowButton("Done").click()
    }

    /// The Quick Look panel is a system window a test can't reliably assert on, so what's checked
    /// here is the entry point: the file offers a preview that isn't "go and find it in Finder".
    func testAFileOffersAPreviewRatherThanOnlyTheFinder() {
        app.windowButton("Storage library").click()

        let file = app.staticTexts[UITestSupport.libraryFile]
        XCTAssertTrue(file.waitForExistence(timeout: UITestSupport.timeout), "the seeded file should be on the shelf")
        file.rightClick()

        let quickLook = app.menuItems["Quick Look (Space)"]
        XCTAssertTrue(
            quickLook.waitForExistence(timeout: UITestSupport.timeout),
            "no Quick Look entry on a stored file"
        )
        app.typeKey(.escape, modifierFlags: [])
        app.windowButton("Done").click()
    }

    /// The point of the library: a file put there once ends up on a strip without going near the
    /// filesystem again.
    func testAFileCanBeTakenFromTheLibraryOntoAStrip() {
        app.stripRow(titled: UITestSupport.strips[0]).doubleClick()

        let addFromLibrary = app.windowButton("Add from Library…")
        XCTAssertTrue(
            addFromLibrary.waitForExistence(timeout: UITestSupport.timeout),
            "the editor's attachments section should offer the library"
        )
        addFromLibrary.click()

        let row = app.staticTexts[UITestSupport.libraryFile]
        XCTAssertTrue(row.waitForExistence(timeout: UITestSupport.timeout), "the picker never listed the seeded file")
        row.click()
        app.windowButton("Add 1").click()

        // The strip's own summary of what's attached, which only counts what it actually holds.
        XCTAssertTrue(
            app.staticTexts["1 document"].waitForExistence(timeout: UITestSupport.timeout),
            "the copied file never landed on the strip"
        )
    }
}
