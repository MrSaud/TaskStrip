import XCTest

/// The roll-ups read the board rather than a store of their own, so what's worth driving through
/// the UI is exactly that: complete a strip, and see it turn up under "done recently".
final class RollUpsUITests: XCTestCase {
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

    private func openRollUps(_ item: String) {
        app.openMenu("View")
        let menuItem = app.menuItem(item, in: "View")
        XCTAssertTrue(menuItem.waitForExistence(timeout: UITestSupport.timeout), "no \(item) item in the View menu")
        menuItem.click()
        XCTAssertTrue(
            app.buttons["Done"].waitForExistence(timeout: UITestSupport.timeout),
            "the roll-up sheet never appeared"
        )
    }

    /// A segmented picker's segments come through as radio buttons; the fallback is there in case
    /// a future style change makes them plain buttons.
    private func segment(_ title: String) -> XCUIElement {
        let radio = app.radioButtons[title]
        return radio.exists ? radio : app.buttons[title]
    }

    func testTheStandupStartsOutSayingThereIsNothingToReport() {
        openRollUps("Standup Summary…")
        XCTAssertTrue(app.staticTexts["Nothing completed in the last 24h"].exists)
        XCTAssertTrue(app.staticTexts["Nothing due today or overdue"].exists)
        XCTAssertTrue(app.staticTexts["Nothing blocked"].exists)
        app.buttons["Done"].click()
    }

    func testCompletingAStripPutsItUnderDoneRecently() {
        app.selectStrip(atRowTitled: UITestSupport.strips[0])
        app.openMenu("Strip")
        app.menuItem("Complete", in: "Strip").click()

        openRollUps("Standup Summary…")
        // Asserting the empty label is *gone* rather than that the title is present: the board
        // behind the sheet shows the same title, so its presence would prove nothing.
        XCTAssertFalse(
            app.staticTexts["Nothing completed in the last 24h"].exists,
            "the strip completed a moment ago should be in the standup"
        )
        app.buttons["Done"].click()
    }

    func testTagProgressSaysSoWhenNothingIsTagged() {
        openRollUps("Tag Progress…")
        XCTAssertTrue(
            app.staticTexts["NO TAGGED STRIPS YET"].waitForExistence(timeout: UITestSupport.timeout),
            "the seeded strips carry no tags, so there is nothing to chart"
        )
        app.buttons["Done"].click()
    }

    func testTheSheetSwitchesBetweenTheTwoRollUps() {
        openRollUps("Standup Summary…")
        let tags = segment("Tag Progress")
        XCTAssertTrue(tags.waitForExistence(timeout: UITestSupport.timeout), "no switch between the roll-ups")
        tags.click()
        XCTAssertTrue(app.staticTexts["NO TAGGED STRIPS YET"].waitForExistence(timeout: UITestSupport.timeout))
        app.buttons["Done"].click()
    }
}
