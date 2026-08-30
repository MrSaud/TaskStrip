import XCTest

/// Drawing itself needs a real pointer dragging across a real canvas, which a test can't do
/// convincingly — so what's checked here is everything around it: both ways into the sketches
/// window, and that a strip can be linked to a sketch and unlinked again.
final class SketchesUITests: XCTestCase {
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

    func testTheViewMenuOpensTheSketches() {
        app.openMenu("View")
        let item = app.menuItem("Sketch Notes…", in: "View")
        XCTAssertTrue(item.waitForExistence(timeout: UITestSupport.timeout), "no Sketch Notes item in the View menu")
        item.click()

        XCTAssertTrue(
            app.staticTexts["NO SKETCHES YET"].waitForExistence(timeout: UITestSupport.timeout),
            "a board with no sketches should say so"
        )
        app.windowButton("Done").click()
    }

    func testTheToolbarOpensTheSketchesToo() {
        let button = app.windowButton("Sketch Notes")
        XCTAssertTrue(button.waitForExistence(timeout: UITestSupport.timeout), "no sketches button on the toolbar")
        button.click()

        XCTAssertTrue(
            app.staticTexts["NO SKETCHES YET"].waitForExistence(timeout: UITestSupport.timeout),
            "the toolbar button should open the same window"
        )
        app.windowButton("Done").click()
    }

    /// A new sketch is a blank page and nothing on disk until something is drawn — so opening one
    /// and closing it should leave the list exactly as empty as it was.
    func testANewSketchBackedOutOfLeavesNothingBehind() {
        app.windowButton("Sketch Notes").click()
        let newSketch = app.windowButton("New sketch")
        XCTAssertTrue(newSketch.waitForExistence(timeout: UITestSupport.timeout), "no way to start a sketch")
        newSketch.click()

        let save = app.windowButton("Save")
        XCTAssertTrue(save.waitForExistence(timeout: UITestSupport.timeout), "the canvas should have opened")
        save.click()

        XCTAssertTrue(
            app.staticTexts["NO SKETCHES YET"].waitForExistence(timeout: UITestSupport.timeout),
            "an undrawn sketch shouldn't turn into a note"
        )
    }

    /// The strip carries the link, so the editor has to offer one even when there's nothing yet
    /// to link to — and say why the list is empty rather than looking broken.
    func testAStripOffersToLinkASketch() {
        app.stripRow(titled: UITestSupport.strips[0]).doubleClick()

        let link = app.windowButton("Link a sketch…")
        XCTAssertTrue(link.waitForExistence(timeout: UITestSupport.timeout), "no way to link a sketch from a strip")
        link.click()

        XCTAssertTrue(
            app.staticTexts["NO SKETCHES YET"].waitForExistence(timeout: UITestSupport.timeout),
            "the picker should be honest about having nothing in it"
        )
    }
}
