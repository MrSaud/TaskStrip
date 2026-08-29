import XCTest

/// Does the menu bar actually get wired up?
///
/// `BoardCommandMenus` reads a `BoardCommandTarget` the board publishes through
/// `focusedSceneValue`. If that never reaches the menu bar, every item in Strip and View stays
/// permanently greyed out and the menus are decoration — which is not something reading the code
/// can tell you. These tests are the check: an item that goes from disabled to enabled when a
/// strip is selected can only have got there through the focused value.
final class MenuBarUITests: XCTestCase {
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

    // MARK: - The menus exist at all

    func testTheStripMenuIsInTheMenuBar() {
        XCTAssertTrue(
            app.menuBars.menuBarItems["Strip"].waitForExistence(timeout: UITestSupport.timeout),
            "CommandMenu(\"Strip\") never made it into the menu bar"
        )
    }

    func testNewStripReplacedNewWindowInTheFileMenu() {
        app.openMenu("File")
        XCTAssertTrue(app.menuItem("New Strip", in: "File").exists, "cmd-N should file a strip")
        XCTAssertFalse(app.menuItem("New Window", in: "File").exists, "New Window should have been replaced")
        XCTAssertTrue(app.menuItem("Import Android Backup…", in: "File").exists)
        app.closeMenu()
    }

    // MARK: - The focused-value wiring

    func testTheStripMenuIsFullyStockedWithNothingSelected() {
        app.openMenu("Strip")
        for title in ["Complete", "Edit…", "Archive", "Delete"] {
            let item = app.menuItem(title, in: "Strip")
            XCTAssertTrue(item.exists, "\(title) is missing from the Strip menu")
            // Enabled even with nothing selected, deliberately: a menu item that starts disabled
            // never gets its key equivalent honoured until the menu is opened once. They no-op
            // without a selection.
            XCTAssertTrue(item.isEnabled, "\(title) should stay enabled so its shortcut works cold")
        }
        app.closeMenu()
    }

    /// The moves keep their gating, so they're what proves the focused value is live.
    func testMoveActionsAreDisabledWithNothingSelected() {
        app.openMenu("Strip")
        for move in ["Move Up", "Move Down", "Move to Top", "Move to Bottom"] {
            XCTAssertFalse(
                app.menuItem(move, in: "Strip").isEnabled,
                "\(move) should be disabled with no strip selected"
            )
        }
        app.closeMenu()
    }

    /// The load-bearing one. A middle strip can move in all four directions, and those items are
    /// disabled until something is selected — so them lighting up can only have happened by way
    /// of the focused scene value.
    func testSelectingAStripEnablesTheMoveActions() {
        app.selectStrip(atRowTitled: UITestSupport.strips[1])

        app.openMenu("Strip")
        for move in ["Move Up", "Move Down", "Move to Top", "Move to Bottom"] {
            XCTAssertTrue(
                app.menuItem(move, in: "Strip").isEnabled,
                "\(move) is still disabled after selecting a strip — the board's focusedSceneValue isn't reaching the menu bar"
            )
        }
        app.closeMenu()
    }

    /// Per-item enablement, not just "something is selected": the top strip has nowhere to go up.
    func testMoveItemsFollowThePositionOfTheSelectedStrip() {
        app.selectStrip(atRowTitled: UITestSupport.strips[0])
        app.openMenu("Strip")
        XCTAssertFalse(app.menuItem("Move Up", in: "Strip").isEnabled, "the top strip can't move up")
        XCTAssertFalse(app.menuItem("Move to Top", in: "Strip").isEnabled, "the top strip is already at the top")
        XCTAssertTrue(app.menuItem("Move Down", in: "Strip").isEnabled)
        app.closeMenu()

        app.selectStrip(atRowTitled: UITestSupport.strips.last!)
        app.openMenu("Strip")
        XCTAssertTrue(app.menuItem("Move Up", in: "Strip").isEnabled)
        XCTAssertFalse(app.menuItem("Move Down", in: "Strip").isEnabled, "the bottom strip can't move down")
        app.closeMenu()
    }

    /// End to end through the menu bar rather than the model: the board should visibly reorder.
    func testMoveToBottomThroughTheMenuReordersTheBoard() {
        XCTAssertTrue(app.waitForBoard(UITestSupport.strips.map { $0.uppercased() }))

        app.selectStrip(atRowTitled: UITestSupport.strips[0])
        app.openMenu("Strip")
        app.menuItem("Move to Bottom", in: "Strip").click()

        let expected = Array(UITestSupport.strips.dropFirst() + [UITestSupport.strips[0]])
            .map { $0.uppercased() }
        XCTAssertTrue(
            app.waitForBoard(expected),
            "board is \(app.boardTitles()), expected \(expected)"
        )
    }

    func testShowAllIsOffUntilTheBoardIsNarrowed() {
        app.openMenu("View")
        XCTAssertTrue(app.menuItem("Show All Strips", in: "View").exists)
        XCTAssertFalse(
            app.menuItem("Show All Strips", in: "View").isEnabled,
            "nothing is filtering the board yet"
        )
        app.closeMenu()
    }
}
