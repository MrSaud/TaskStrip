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
        XCTAssertTrue(app.menuItem("New Strip").exists, "cmd-N should file a strip")
        XCTAssertFalse(app.menuItem("New Window").exists, "New Window should have been replaced")
        XCTAssertTrue(app.menuItem("Import Android Backup…").exists)
        app.closeMenu()
    }

    // MARK: - The focused-value wiring

    func testStripActionsAreDisabledWithNothingSelected() {
        app.openMenu("Strip")
        for title in ["Complete", "Edit…", "Archive", "Delete"] {
            let item = app.menuItem(title)
            XCTAssertTrue(item.exists, "\(title) is missing from the Strip menu")
            XCTAssertFalse(item.isEnabled, "\(title) should be disabled with no strip selected")
        }
        app.closeMenu()
    }

    /// The load-bearing one. Selecting a row can only enable these items by way of the focused
    /// scene value, so this passing means the wiring works end to end.
    func testSelectingAStripEnablesTheStripMenu() {
        app.selectStrip(atRowTitled: UITestSupport.strips[1])

        app.openMenu("Strip")
        for title in ["Complete", "Edit…", "Archive", "Delete"] {
            XCTAssertTrue(
                app.menuItem(title).isEnabled,
                "\(title) is still disabled after selecting a strip — the board's focusedSceneValue isn't reaching the menu bar"
            )
        }
        app.closeMenu()
    }

    /// Per-item enablement, not just "something is selected": the top strip has nowhere to go up.
    func testMoveItemsFollowThePositionOfTheSelectedStrip() {
        app.selectStrip(atRowTitled: UITestSupport.strips[0])
        app.openMenu("Strip")
        XCTAssertFalse(app.menuItem("Move Up").isEnabled, "the top strip can't move up")
        XCTAssertFalse(app.menuItem("Move to Top").isEnabled, "the top strip is already at the top")
        XCTAssertTrue(app.menuItem("Move Down").isEnabled)
        app.closeMenu()

        app.selectStrip(atRowTitled: UITestSupport.strips.last!)
        app.openMenu("Strip")
        XCTAssertTrue(app.menuItem("Move Up").isEnabled)
        XCTAssertFalse(app.menuItem("Move Down").isEnabled, "the bottom strip can't move down")
        app.closeMenu()
    }

    /// End to end through the menu bar rather than the model: the board should visibly reorder.
    func testMoveToBottomThroughTheMenuReordersTheBoard() {
        XCTAssertTrue(app.waitForBoard(UITestSupport.strips.map { $0.uppercased() }))

        app.selectStrip(atRowTitled: UITestSupport.strips[0])
        app.openMenu("Strip")
        app.menuItem("Move to Bottom").click()

        let expected = Array(UITestSupport.strips.dropFirst() + [UITestSupport.strips[0]])
            .map { $0.uppercased() }
        XCTAssertTrue(
            app.waitForBoard(expected),
            "board is \(app.boardTitles()), expected \(expected)"
        )
    }

    func testShowAllIsOffUntilTheBoardIsNarrowed() {
        app.openMenu("View")
        XCTAssertTrue(app.menuItem("Show All Strips").exists)
        XCTAssertFalse(
            app.menuItem("Show All Strips").isEnabled,
            "nothing is filtering the board yet"
        )
        app.closeMenu()
    }
}
