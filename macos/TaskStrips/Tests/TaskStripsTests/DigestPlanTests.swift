import XCTest
@testable import TaskStrips

/// Times, wording, and the rule that keeps a digest from becoming noise. What actually posts the
/// notification is untestable here; what it would say is not.
final class DigestPlanTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func parts(_ date: Date?) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date!)
    }

    private func strip(
        _ title: String,
        due: Date? = nil,
        done: Bool = false,
        completedAt: Date? = nil,
        archived: Bool = false
    ) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: 0)
        task.dueAt = due
        task.isDone = done
        task.completedAt = completedAt
        task.isArchived = archived
        return task
    }

    // MARK: - When they fire

    func testTheMorningDigestIsAtEightTheSameDayIfItHasNotPassed() {
        let next = parts(DigestPlan.nextDaily(after: date(2026, 8, 30, 6), calendar: calendar))
        XCTAssertEqual(next.day, 30)
        XCTAssertEqual(next.hour, 8)
        XCTAssertEqual(next.minute, 0)
    }

    func testAfterEightItIsTomorrow() {
        let next = parts(DigestPlan.nextDaily(after: date(2026, 8, 30, 9), calendar: calendar))
        XCTAssertEqual(next.day, 31)
        XCTAssertEqual(next.hour, 8)
    }

    /// Strictly after, so re-arming at the moment one fires lands on the next one rather than on
    /// itself.
    func testRearmingAtTheExactMomentMovesOn() {
        let next = parts(DigestPlan.nextDaily(after: date(2026, 8, 30, 8, 0), calendar: calendar))
        XCTAssertEqual(next.day, 31)
    }

    func testTheReviewIsFridayAtFive() {
        // 30 Aug 2026 is a Sunday.
        let next = parts(DigestPlan.nextWeekly(after: date(2026, 8, 30, 12), calendar: calendar))
        XCTAssertEqual(next.weekday, 6, "6 is Friday in Calendar's numbering")
        XCTAssertEqual(next.hour, 17)
        XCTAssertEqual(next.day, 4)
        XCTAssertEqual(next.month, 9)
    }

    func testFridayMorningStillGetsThatAfternoonsReview() {
        let next = parts(DigestPlan.nextWeekly(after: date(2026, 9, 4, 9), calendar: calendar))
        XCTAssertEqual(next.day, 4)
        XCTAssertEqual(next.hour, 17)
    }

    func testTheBackupHourIsTheQuietOne() {
        let next = parts(DigestPlan.nextBackup(after: date(2026, 8, 30, 12), calendar: calendar))
        XCTAssertEqual(next.hour, 3)
        XCTAssertEqual(next.day, 31)
    }

    // MARK: - The morning digest

    /// Asked about the morning it will fire, not about tonight — the whole reason the content is
    /// computed for the fire date.
    func testTheDigestDescribesTheDayItFiresOn() {
        let tomorrow = strip("Due tomorrow", due: date(2026, 8, 31, 9))
        let today = strip("Due today", due: date(2026, 8, 30, 9))

        let tonight = date(2026, 8, 30, 23)
        let fireAt = DigestPlan.nextDaily(after: tonight, calendar: calendar)!
        let digest = DigestPlan.daily(for: [tomorrow, today], on: fireAt, calendar: calendar)

        XCTAssertEqual(digest.total, 2, "by 8am tomorrow, both are due or overdue")
        XCTAssertEqual(
            DigestPlan.daily(for: [tomorrow, today], on: tonight, calendar: calendar).total,
            1,
            "asked about tonight, only today's is due"
        )
    }

    func testADoneOrArchivedStripIsNotDue() {
        let due = date(2026, 8, 30, 9)
        let tasks = [
            strip("Done", due: due, done: true),
            strip("Archived", due: due, archived: true),
            strip("Open", due: due),
        ]
        XCTAssertEqual(DigestPlan.daily(for: tasks, on: date(2026, 8, 30, 8), calendar: calendar).titles, ["OPEN"])
    }

    /// A digest that arrives every morning to report an empty board is one people turn off.
    func testNothingDueMeansNothingIsSaid() {
        XCTAssertTrue(DigestPlan.daily(for: [], on: date(2026, 8, 30, 8), calendar: calendar).isEmpty)
        XCTAssertTrue(
            DigestPlan.daily(for: [strip("Someday")], on: date(2026, 8, 30, 8), calendar: calendar).isEmpty
        )
    }

    func testTheDigestNamesFiveAndCountsTheRest() {
        let due = date(2026, 8, 30, 9)
        let tasks = (1...8).map { strip("Strip \($0)", due: due) }
        let digest = DigestPlan.daily(for: tasks, on: date(2026, 8, 30, 8), calendar: calendar)

        XCTAssertEqual(digest.title, "8 strips need attention today")
        XCTAssertEqual(digest.titles.count, 5)
        XCTAssertTrue(digest.body.hasSuffix("+ 3 more"), "got \(digest.body)")
        XCTAssertTrue(digest.body.hasPrefix("STRIP 1"), "rows read as they do on the board")
    }

    func testOneStripReadsAsOne() {
        let digest = DigestPlan.daily(
            for: [strip("Renew the passport", due: date(2026, 8, 30, 9))],
            on: date(2026, 8, 30, 8),
            calendar: calendar
        )
        XCTAssertEqual(digest.title, "1 strip needs attention today")
        XCTAssertEqual(digest.body, "RENEW THE PASSPORT")
    }

    // MARK: - The Friday review

    func testTheReviewCountsTheWeeksWorkAndWhatIsStillLate() {
        let friday = date(2026, 9, 4, 17)
        let tasks = [
            strip("Done Monday", done: true, completedAt: date(2026, 8, 31, 10)),
            strip("Done last month", done: true, completedAt: date(2026, 7, 20, 10)),
            strip("Late", due: date(2026, 8, 20, 9)),
        ]
        let review = DigestPlan.weekly(for: tasks, on: friday, calendar: calendar)

        XCTAssertEqual(review.done, 1)
        XCTAssertEqual(review.overdue, 1)
        XCTAssertEqual(review.title, "Week in review")
        XCTAssertEqual(review.body, "1 strip done · 1 still overdue")
    }

    func testAQuietWeekSaysNothing() {
        XCTAssertTrue(DigestPlan.weekly(for: [], on: date(2026, 9, 4, 17), calendar: calendar).isEmpty)
    }

    func testTheReviewPluralisesBothHalves() {
        let friday = date(2026, 9, 4, 17)
        let tasks = [
            strip("A", done: true, completedAt: date(2026, 9, 1)),
            strip("B", done: true, completedAt: date(2026, 9, 2)),
            strip("C", due: date(2026, 8, 20)),
            strip("D", due: date(2026, 8, 21)),
        ]
        XCTAssertEqual(
            DigestPlan.weekly(for: tasks, on: friday, calendar: calendar).body,
            "2 strips done · 2 still overdue"
        )
    }

    // MARK: - The automatic backup

    func testABackupIsOwedOnceADayHasPassed() {
        let now = date(2026, 8, 30, 12)
        XCTAssertTrue(DigestPlan.isBackupDue(lastBackup: nil, now: now), "never backed up")
        XCTAssertTrue(DigestPlan.isBackupDue(lastBackup: now.addingTimeInterval(-24 * 3600), now: now))
        XCTAssertFalse(DigestPlan.isBackupDue(lastBackup: now.addingTimeInterval(-23 * 3600), now: now))
    }

    /// Opening the app twice in an afternoon shouldn't upload twice.
    func testTheSecondLaunchOfTheDayOwesNothing() {
        let now = date(2026, 8, 30, 16)
        XCTAssertFalse(DigestPlan.isBackupDue(lastBackup: date(2026, 8, 30, 9), now: now))
    }
}
