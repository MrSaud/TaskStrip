import XCTest

/// Does clicking a row still work?
///
/// 991191a wrapped each row in a Button because a bare `.onTapGesture` wouldn't reliably open the
/// editor on a macOS List row. Adding a selection meant that Button had to go — a Button swallows
/// the click selection needs — so single-click-to-select and double-click-to-open are both
/// unproven. If double-click turns out not to fire, `testCommandEOpensTheEditor` is the evidence
/// that the keyboard path still gets you in.
final class BoardInteractionUITests: XCTestCase {
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

    func testTheSeededBoardRenders() {
        XCTAssertTrue(
            app.waitForBoard(UITestSupport.strips.map { $0.uppercased() }),
            "board is \(app.boardTitles())"
        )
    }

    func testDoubleClickOpensTheEditorForThatStrip() {
        app.stripRow(titled: UITestSupport.strips[1]).doubleClick()

        XCTAssertTrue(
            app.buttons["Update"].waitForExistence(timeout: UITestSupport.timeout),
            "double-clicking a row didn't open the edit sheet"
        )
        // "Update" rather than "File Strip", and a delete button at all, means it opened *this*
        // strip rather than a blank new one.
        XCTAssertTrue(app.buttons["DELETE STRIP"].exists)

        app.buttons["Cancel"].firstMatch.click()
    }

    /// The one the refactor was for. Pressed cold, with the Strip menu never opened: this used to
    /// fail because the focused value was a struct of closures SwiftUI couldn't diff, so the menu
    /// was only ever rebuilt on open and the key equivalent went nowhere.
    func testTheEditShortcutOpensTheEditorForTheSelectedStrip() {
        app.selectStrip(atRowTitled: UITestSupport.strips[0])
        app.typeKey("e", modifierFlags: [.command, .shift])

        XCTAssertTrue(
            app.buttons["Update"].waitForExistence(timeout: UITestSupport.timeout),
            "the Edit shortcut didn't open the editor"
        )
        app.buttons["Cancel"].firstMatch.click()
    }

    func testTheEditShortcutWorksOnceTheStripMenuHasBeenOpened() {
        app.selectStrip(atRowTitled: UITestSupport.strips[0])
        app.openMenu("Strip")
        app.closeMenu()
        app.typeKey("e", modifierFlags: [.command, .shift])

        XCTAssertTrue(
            app.buttons["Update"].waitForExistence(timeout: UITestSupport.timeout),
            "the Edit shortcut didn't work even after the menu had been realised"
        )
        app.buttons["Cancel"].firstMatch.click()
    }

    /// The menu item itself, independent of any key equivalent.
    func testTheEditMenuItemOpensTheEditorForTheSelectedStrip() {
        app.selectStrip(atRowTitled: UITestSupport.strips[0])
        app.openMenu("Strip")
        app.menuItem("Edit…", in: "Strip").click()

        XCTAssertTrue(
            app.buttons["Update"].waitForExistence(timeout: UITestSupport.timeout),
            "Edit… in the Strip menu didn't open the editor"
        )
        app.buttons["Cancel"].firstMatch.click()
    }

    func testCommandNOpensANewStripRatherThanASecondWindow() {
        let windowsBefore = app.windows.count
        app.typeKey("n", modifierFlags: .command)

        XCTAssertTrue(
            app.buttons["File Strip"].waitForExistence(timeout: UITestSupport.timeout),
            "cmd-N should open the new-strip sheet"
        )
        XCTAssertLessThanOrEqual(windowsBefore, app.windows.count)
        app.buttons["Cancel"].firstMatch.click()
    }

    /// Deleting from the board used to be instant and permanent; it should ask now.
    func testDeletingFromTheMenuAsksFirst() {
        app.selectStrip(atRowTitled: UITestSupport.strips[1])
        app.openMenu("Strip")
        app.menuItem("Delete", in: "Strip").click()

        let cancel = app.confirmationButton("Cancel")
        XCTAssertTrue(
            cancel.waitForExistence(timeout: UITestSupport.timeout),
            "board delete went straight through without confirming"
        )
        cancel.click()

        XCTAssertTrue(
            app.waitForBoard(UITestSupport.strips.map { $0.uppercased() }),
            "cancelling the confirmation should leave the board alone — board is \(app.boardTitles())"
        )
    }
}
