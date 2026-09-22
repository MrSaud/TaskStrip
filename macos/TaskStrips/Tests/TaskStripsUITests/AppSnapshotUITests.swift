import XCTest

/// Not an assertion — a way to look at the app.
///
/// The Mac port is developed from a Linux container with no macOS, so the only place it ever
/// actually runs is here. Screenshots can't come back (the artifact host is blocked), but the
/// accessibility hierarchy can: it's a faithful text rendering of what's on screen, element by
/// element, and it travels through the build log.
///
/// Asserts nothing beyond the app having launched, so it can't turn CI red on its own.
final class AppSnapshotUITests: XCTestCase {
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

    func testDescribeTheBoardAsLaunched() {
        XCTAssertTrue(
            app.stripRow(titled: UITestSupport.strips[0]).waitForExistence(timeout: UITestSupport.timeout)
        )

        print("===== BOARD WINDOW =====")
        print(app.windows.firstMatch.debugDescription)

        print("===== MENU BAR =====")
        for menu in ["File", "Edit", "View", "Strip", "Window"] {
            let item = app.menuBars.menuBarItems[menu]
            print("menu \"\(menu)\": exists=\(item.exists)")
        }
    }

    func testDescribeTheStripMenuWithAStripSelected() {
        app.selectStrip(atRowTitled: UITestSupport.strips[1])
        app.openMenu("Strip")

        print("===== STRIP MENU, \"\(UITestSupport.strips[1])\" SELECTED =====")
        for title in ["Complete", "Edit…", "Move Up", "Move Down", "Move to Top",
                      "Move to Bottom", "Archive", "Delete"] {
            let item = app.menuItem(title, in: "Strip")
            print(String(format: "  %-16s exists=%@ enabled=%@",
                         (title as NSString).utf8String!,
                         item.exists ? "yes" : "no",
                         item.exists && item.isEnabled ? "yes" : "no"))
        }
        app.closeMenu()
    }

    func testDescribeTheEditorForAStrip() {
        app.stripRow(titled: UITestSupport.strips[0]).doubleClick()
        XCTAssertTrue(app.buttons["Update"].waitForExistence(timeout: UITestSupport.timeout))

        print("===== EDIT SHEET =====")
        print(app.windows.firstMatch.debugDescription)

        app.buttons["Cancel"].firstMatch.click()
    }
}
