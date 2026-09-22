import XCTest
@testable import TaskStrips

/// A roll-up's answer depends on the clock, so every case here pins `now` rather than trusting
/// the machine's.
final class StandupSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Mid-morning, spelled out rather than written as an epoch number: "six hours from now" only
    /// means "later today" if you know where in the day `now` sits, and a magic constant doesn't
    /// tell you. 1_780_000_000 was 20:26 UTC, which quietly made that case tomorrow.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9))!
    }

    private func strip(_ title: String, orderIndex: Int = 0) -> TaskItem {
        TaskItem(title: title, orderIndex: orderIndex)
    }

    private func summary(_ tasks: [TaskItem]) -> StandupSummary {
        StandupSummary.make(from: tasks, now: now, calendar: calendar)
    }

    // MARK: - Done recently

    func testCountsWhatWasCompletedInTheLastDay() {
        let fresh = strip("Filed the form")
        fresh.isDone = true
        fresh.completedAt = now.addingTimeInterval(-3600)

        let stale = strip("Booked the flight")
        stale.isDone = true
        stale.completedAt = now.addingTimeInterval(-StandupSummary.recentWindow - 60)

        XCTAssertEqual(summary([fresh, stale]).doneRecently.map(\.title), ["Filed the form"])
    }

    /// A strip marked done before completedAt was ever recorded has nothing to date, and dating
    /// it "now" would put it in every standup forever.
    func testADoneStripWithNoCompletionDateIsNotRecent() {
        let task = strip("Whenever this happened")
        task.isDone = true
        XCTAssertTrue(summary([task]).doneRecently.isEmpty)
    }

    func testAnOpenStripIsNotDone() {
        let task = strip("Still going")
        task.completedAt = now
        XCTAssertTrue(summary([task]).doneRecently.isEmpty)
    }

    // MARK: - Planned today

    func testPlannedTodayCoversTodayAndAnythingOverdue() {
        let today = strip("Due later today")
        today.dueAt = now.addingTimeInterval(6 * 3600)

        let overdue = strip("Due last week")
        overdue.dueAt = now.addingTimeInterval(-7 * 24 * 3600)

        let later = strip("Due tomorrow")
        later.dueAt = now.addingTimeInterval(36 * 3600)

        XCTAssertEqual(
            summary([today, overdue, later]).plannedToday.map(\.title),
            ["Due later today", "Due last week"]
        )
    }

    /// Whole days, not a rolling 24 hours: something due at 9am is still today's work at 5pm.
    func testSomethingDueEarlierTodayIsStillPlannedToday() {
        let task = strip("This morning")
        task.dueAt = calendar.startOfDay(for: now)
        XCTAssertEqual(summary([task]).plannedToday.map(\.title), ["This morning"])
    }

    func testADoneStripIsNotStillPlanned() {
        let task = strip("Already handled")
        task.dueAt = now
        task.isDone = true
        XCTAssertTrue(summary([task]).plannedToday.isEmpty)
    }

    func testAStripWithNoDueDateIsNotPlannedToday() {
        XCTAssertTrue(summary([strip("Someday")]).plannedToday.isEmpty)
    }

    // MARK: - Blockers

    func testAStripWaitingOnAnUnfinishedOneIsBlocked() {
        let blocker = strip("Get the reference number", orderIndex: 0)
        let blocked = strip("Submit the application", orderIndex: 1)
        blocked.blockedByID = blocker.id

        XCTAssertEqual(summary([blocker, blocked]).blocked.map(\.title), ["Submit the application"])
    }

    func testOnceTheBlockerIsDoneNothingIsBlocked() {
        let blocker = strip("Get the reference number")
        blocker.isDone = true
        let blocked = strip("Submit the application")
        blocked.blockedByID = blocker.id

        XCTAssertTrue(summary([blocker, blocked]).blocked.isEmpty)
    }

    /// The roll-up only ever sees the board, so a blocker that has been archived off it can't be
    /// found — and an archived strip holding up today's work isn't a blocker worth reporting.
    func testABlockerThatIsNotOnTheBoardDoesNotCount() {
        let blocked = strip("Submit the application")
        blocked.blockedByID = UUID()
        XCTAssertTrue(summary([blocked]).blocked.isEmpty)
    }

    func testACompletedStripIsNeverBlocked() {
        let blocker = strip("Get the reference number")
        let blocked = strip("Submit the application")
        blocked.blockedByID = blocker.id
        blocked.isDone = true

        XCTAssertTrue(summary([blocker, blocked]).blocked.isEmpty)
    }

    // MARK: - The pasteable text

    func testTheTextCarriesEverySection() {
        let done = strip("Filed the form")
        done.isDone = true
        done.completedAt = now
        let due = strip("Renew the lease")
        due.dueAt = now

        let text = summary([done, due]).plainText
        XCTAssertTrue(text.hasPrefix("STANDUP SUMMARY"))
        XCTAssertTrue(text.contains("Done recently:\n- Filed the form"))
        XCTAssertTrue(text.contains("Planned today:\n- Renew the lease"))
        XCTAssertTrue(text.contains("Blockers:\n- (none)"))
    }

    func testAnEmptyBoardStillReadsAsAStandup() {
        let text = summary([]).plainText
        XCTAssertTrue(text.contains("Done recently:\n- (nothing)"))
        XCTAssertTrue(text.contains("Planned today:\n- (nothing)"))
        XCTAssertTrue(text.contains("Blockers:\n- (none)"))
        XCTAssertTrue(summary([]).isEmpty)
    }
}
