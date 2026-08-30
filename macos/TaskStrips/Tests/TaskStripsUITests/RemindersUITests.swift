import XCTest

/// The standalone reminders, driven through the list and its editor. Nothing here asks the system
/// for notification permission — the scheduler is off under UI testing precisely so a permission
/// dialog can't derail the suite.
final class RemindersUITests: XCTestCase {
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

    private func openReminders() {
        app.openMenu("View")
        let item = app.menuItem("Reminders…", in: "View")
        XCTAssertTrue(item.waitForExistence(timeout: UITestSupport.timeout), "no Reminders item in the View menu")
        item.click()
        XCTAssertTrue(
            app.staticTexts["NO REMINDERS YET"].waitForExistence(timeout: UITestSupport.timeout),
            "a fresh list should say it's empty"
        )
    }

    func testTheViewMenuOpensTheReminders() {
        openReminders()
        app.windowButton("Done").click()
    }

    func testAReminderCanBeMadeAndComesBackInTheList() {
        openReminders()
        app.windowButton("New Reminder").click()

        let title = app.textFields["reminderTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: UITestSupport.timeout), "the editor never opened")
        title.click()
        title.typeText("Renew the registration")
        app.windowButton("Create").click()

        XCTAssertTrue(
            app.staticTexts["Renew the registration"].waitForExistence(timeout: UITestSupport.timeout),
            "the new reminder never reached the list"
        )
        app.windowButton("Done").click()
    }

    /// A reminder with no title would be a row you can't read, so the editor won't take one.
    func testAnUntitledReminderCannotBeCreated() {
        openReminders()
        app.windowButton("New Reminder").click()

        let create = app.windowButton("Create")
        XCTAssertTrue(create.waitForExistence(timeout: UITestSupport.timeout))
        XCTAssertFalse(create.isEnabled, "Create should stay off until there's something to call it")
        app.windowButton("Cancel").click()
    }
}
