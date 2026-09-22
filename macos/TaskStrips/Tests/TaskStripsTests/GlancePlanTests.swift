import XCTest
@testable import TaskStrips

/// What the menu bar shows, and in what order. The menu itself can't be opened from a test; the
/// choosing can.
final class GlancePlanTests: XCTestCase {
    private func strip(
        _ title: String,
        order: Int,
        done: Bool = false,
        archived: Bool = false
    ) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: order)
        task.isDone = done
        task.isArchived = archived
        return task
    }

    private func reminder(_ text: String, at triggerAt: Date, done: Bool = false) -> Reminder {
        Reminder(text: text, triggerAt: triggerAt, isDone: done)
    }

    private func date(_ offsetDays: Double) -> Date {
        Date(timeIntervalSince1970: 1_780_000_000).addingTimeInterval(offsetDays * 24 * 3600)
    }

    // MARK: - Strips

    /// Board order, not due order: the glance shows the top of the board, which is the order the
    /// user themselves put it in.
    func testStripsComeInBoardOrder() {
        let tasks = [strip("Third", order: 2), strip("First", order: 0), strip("Second", order: 1)]
        XCTAssertEqual(GlancePlan.strips(from: tasks).map(\.title), ["First", "Second", "Third"])
    }

    func testFinishedAndArchivedStripsAreNotAGlance() {
        let tasks = [
            strip("Open", order: 0),
            strip("Done", order: 1, done: true),
            strip("Archived", order: 2, archived: true),
        ]
        XCTAssertEqual(GlancePlan.strips(from: tasks).map(\.title), ["Open"])
    }

    func testAtMostFiveStrips() {
        let tasks = (0..<9).map { strip("Strip \($0)", order: $0) }
        XCTAssertEqual(GlancePlan.strips(from: tasks).count, GlancePlan.stripLimit)
        XCTAssertEqual(GlancePlan.strips(from: tasks).last?.title, "Strip 4")
    }

    /// The count beside the list is of everything open, not of the five shown — otherwise it
    /// would always read five.
    func testTheCountIsOfEverythingOpen() {
        let tasks = (0..<9).map { strip("Strip \($0)", order: $0) } + [strip("Done", order: 9, done: true)]
        XCTAssertEqual(GlancePlan.openCount(tasks), 9)
    }

    func testAClearBoardCountsNothing() {
        XCTAssertEqual(GlancePlan.openCount([strip("Done", order: 0, done: true)]), 0)
        XCTAssertTrue(GlancePlan.strips(from: []).isEmpty)
    }

    // MARK: - Reminders

    /// Soonest first, because that's the only order a reminder has.
    func testRemindersComeSoonestFirst() {
        let items = [
            reminder("Later", at: date(3)),
            reminder("Sooner", at: date(1)),
            reminder("Middle", at: date(2)),
        ]
        XCTAssertEqual(GlancePlan.reminders(from: items).map(\.text), ["Sooner", "Middle", "Later"])
    }

    func testFinishedRemindersAreNotPending() {
        let items = [reminder("Done", at: date(1), done: true), reminder("Open", at: date(2))]
        XCTAssertEqual(GlancePlan.reminders(from: items).map(\.text), ["Open"])
    }

    func testAtMostThreeReminders() {
        let items = (0..<6).map { reminder("Reminder \($0)", at: date(Double($0))) }
        XCTAssertEqual(GlancePlan.reminders(from: items).count, GlancePlan.reminderLimit)
        XCTAssertEqual(GlancePlan.reminders(from: items).last?.text, "Reminder 2")
    }

    /// An overdue reminder is still pending — it sorts first, which is where it belongs.
    func testSomethingOverdueIsStillShown() {
        let items = [reminder("Overdue", at: date(-5)), reminder("Ahead", at: date(5))]
        XCTAssertEqual(GlancePlan.reminders(from: items).map(\.text), ["Overdue", "Ahead"])
    }
}
