import XCTest

/// The scratchpad, end to end: jot something, then turn it into work.
///
/// Worth driving through the UI rather than only unit-testing NotePromotion, because the part
/// that can quietly fail is the wiring — the sheet reaching the board's model context, and the
/// promoted strip actually landing on the board behind it.
final class NotesUITests: XCTestCase {
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

    private func openNotes() {
        app.openMenu("View")
        let item = app.menuItem("Quick Notes…", in: "View")
        XCTAssertTrue(item.waitForExistence(timeout: UITestSupport.timeout), "no Quick Notes item in the View menu")
        item.click()
        XCTAssertTrue(
            app.buttons["Add Note"].waitForExistence(timeout: UITestSupport.timeout),
            "the Quick Notes sheet never appeared"
        )
    }

    private func jot(_ text: String) {
        let editor = app.textViews["noteComposer"]
        XCTAssertTrue(editor.waitForExistence(timeout: UITestSupport.timeout), "no note editor in the sheet")
        editor.click()
        editor.typeText(text)
        app.buttons["Add Note"].click()
    }

    func testTheViewMenuOpensTheScratchpad() {
        openNotes()
        XCTAssertTrue(app.staticTexts["NO NOTES YET"].exists, "a fresh scratchpad should say it's empty")
        app.buttons["Done"].click()
    }

    func testAJottedNoteSticksAround() {
        openNotes()
        jot("call the consulate")
        XCTAssertTrue(
            app.staticTexts["call the consulate"].waitForExistence(timeout: UITestSupport.timeout),
            "the note never appeared in the list"
        )
        app.buttons["Done"].click()
    }

    func testPromotingANoteFilesAStripOnTheBoard() {
        openNotes()
        jot("Renew the lease")

        let promote = app.buttons["Promote to Strip"]
        XCTAssertTrue(promote.waitForExistence(timeout: UITestSupport.timeout), "no promote button on the note")
        promote.click()

        // The note is consumed by the promotion — Android does the same.
        XCTAssertTrue(app.staticTexts["NO NOTES YET"].waitForExistence(timeout: UITestSupport.timeout))
        app.buttons["Done"].click()

        XCTAssertTrue(
            app.staticTexts["RENEW THE LEASE"].waitForExistence(timeout: UITestSupport.timeout),
            "the promoted strip never reached the board"
        )
    }

    func testSplitIsOnlyOfferedOnceThereIsMoreThanOneLine() {
        openNotes()
        jot("just the one line")
        XCTAssertFalse(app.buttons["Split into Strips"].exists, "a single-line note has nothing to split")

        // Return inserts a line here, exactly as it does on Android — the button is what files it.
        jot("first thing\nsecond thing")
        XCTAssertTrue(
            app.buttons["Split into Strips"].firstMatch.waitForExistence(timeout: UITestSupport.timeout),
            "a two-line note should offer the split"
        )
        app.buttons["Done"].click()
    }
}
