import SwiftData
import XCTest
@testable import TaskStrips

/// What the week quietly didn't do — the strips that say nothing, which is why nothing else
/// brings them up.
@MainActor
final class WeeklyReviewTests: XCTestCase {
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    @discardableResult
    private func strip(_ title: String, quietDays: Int = 0) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: 0, createdAt: now.addingTimeInterval(-90 * 86_400))
        task.updatedAt = now.addingTimeInterval(Double(-quietDays) * 86_400)
        context.insert(task)
        return task
    }

    func testAStripNobodyHasTouchedInAFortnightIsStalled() {
        strip("Forgotten thing", quietDays: 20)
        strip("Touched yesterday", quietDays: 1)
        let review = WeeklyReview.make(from: fetch(), now: now)
        XCTAssertEqual(review.stalled.map(\.title), ["Forgotten thing"])
    }

    /// Anything that happened counts, not only an edit: a stretch of work, a logged action, an
    /// entry on a total.
    func testWorkingOnAStripCountsAsActivity() {
        let task = strip("Worked on", quietDays: 30)
        task.sessions = [TaskWorkSession(startedAt: now.addingTimeInterval(-86_400), endedAt: now.addingTimeInterval(-80_000))]
        XCTAssertTrue(WeeklyReview.make(from: fetch(), now: now).stalled.isEmpty)
    }

    func testAddingToATotalCountsAsActivity() {
        let task = strip("Counted", quietDays: 30)
        task.tallies = [StripTally.adding(2, to: TaskTally(name: "Hours", unit: .hours), at: now.addingTimeInterval(-86_400))]
        XCTAssertTrue(WeeklyReview.make(from: fetch(), now: now).stalled.isEmpty)
    }

    func testALoggedActionCountsAsActivity() {
        let task = strip("Chased", quietDays: 30)
        task.actionLog = [TaskActionLogEntry(text: "Chased by email", timestamp: now.addingTimeInterval(-2 * 86_400))]
        XCTAssertTrue(WeeklyReview.make(from: fetch(), now: now).stalled.isEmpty)
    }

    /// A strip waiting for its day hasn't stalled; it's asleep on purpose.
    func testADeferredStripIsNotStalled() {
        let task = strip("Later", quietDays: 30)
        task.deferUntil = now.addingTimeInterval(5 * 86_400)
        XCTAssertTrue(WeeklyReview.make(from: fetch(), now: now).stalled.isEmpty)
    }

    func testFinishedAndArchivedStripsAreNotStalled() {
        let done = strip("Done", quietDays: 30)
        done.isDone = true
        let archived = strip("Archived", quietDays: 30)
        archived.isArchived = true
        XCTAssertTrue(WeeklyReview.make(from: fetch(), now: now).stalled.isEmpty)
    }

    // MARK: - Started and left

    func testHalfATickedChecklistLeftForAWeekIsAbandonedRatherThanStalled() {
        let task = strip("Half done", quietDays: 10)
        task.checklist = [
            TaskChecklistItem(text: "One", isDone: true),
            TaskChecklistItem(text: "Two", isDone: false),
        ]
        let review = WeeklyReview.make(from: fetch(), now: now)
        XCTAssertEqual(review.halfFinished.map(\.title), ["Half done"])
        XCTAssertTrue(review.stalled.isEmpty, "it belongs in one list, not both")
    }

    func testAChecklistNobodyHasStartedIsJustAStripLikeAnyOther() {
        let task = strip("Not started", quietDays: 20)
        task.checklist = [TaskChecklistItem(text: "One", isDone: false)]
        let review = WeeklyReview.make(from: fetch(), now: now)
        XCTAssertTrue(review.halfFinished.isEmpty)
        XCTAssertEqual(review.stalled.map(\.title), ["Not started"])
    }

    // MARK: - Waiting

    func testWaitingTwiceAsLongAsAgreedIsTooLong() {
        let task = strip("Waiting", quietDays: 0)
        task.waitingOnName = "Bassam"
        task.waitingOnFollowUpDays = 7
        task.waitingOnSince = now.addingTimeInterval(-15 * 86_400)
        XCTAssertTrue(WeeklyReview.isWaitingTooLong(task, now: now))
    }

    func testAChaseBuysTimeHereToo() {
        let task = strip("Waiting", quietDays: 0)
        task.waitingOnName = "Bassam"
        task.waitingOnFollowUpDays = 7
        task.waitingOnSince = now.addingTimeInterval(-15 * 86_400)
        task.waitingOnChasedAt = now.addingTimeInterval(-86_400)
        XCTAssertFalse(WeeklyReview.isWaitingTooLong(task, now: now))
    }

    /// The case the follow-up notification can't catch: nothing was ever agreed, so nothing fires.
    func testWaitingWithNoFollowUpAgreedIsCaughtAfterAFortnight() {
        let task = strip("Waiting", quietDays: 0)
        task.waitingOnName = "The ministry"
        task.waitingOnSince = now.addingTimeInterval(-20 * 86_400)
        XCTAssertNil(task.waitingOnFollowUpDays)
        XCTAssertTrue(WeeklyReview.isWaitingTooLong(task, now: now))
    }

    // MARK: - Budgets

    func testABudgetThreeQuartersSpentIsWorthMentioning() {
        let task = strip("Fit-out", quietDays: 1)
        var tally = TaskTally(name: "Cost", unit: .money(currency: "KWD"))
        tally.target = 1_000
        tally = StripTally.adding(800, to: tally, at: now)
        task.tallies = [tally]
        XCTAssertEqual(WeeklyReview.make(from: fetch(), now: now).budgetsCreeping.map(\.title), ["Fit-out"])
    }

    func testABudgetHalfSpentIsNot() {
        let task = strip("Fit-out", quietDays: 1)
        var tally = TaskTally(name: "Cost", unit: .money(currency: "KWD"))
        tally.target = 1_000
        tally = StripTally.adding(400, to: tally, at: now)
        task.tallies = [tally]
        XCTAssertTrue(WeeklyReview.make(from: fetch(), now: now).budgetsCreeping.isEmpty)
    }

    func testATotalWithNoTargetCannotCreep() {
        let task = strip("Hours", quietDays: 1)
        task.tallies = [StripTally.adding(900, to: TaskTally(name: "Hours", unit: .hours), at: now)]
        XCTAssertTrue(WeeklyReview.make(from: fetch(), now: now).budgetsCreeping.isEmpty)
    }

    // MARK: - The good news

    /// A review that only lists failures is one nobody opens twice.
    func testWhatWasFinishedThisWeekIsListedToo() {
        let task = strip("Shipped", quietDays: 2)
        task.isDone = true
        task.completedAt = now.addingTimeInterval(-2 * 86_400)
        let old = strip("Shipped last month", quietDays: 40)
        old.isDone = true
        old.completedAt = now.addingTimeInterval(-40 * 86_400)

        let review = WeeklyReview.make(from: fetch(), now: now)
        XCTAssertEqual(review.finished.map(\.title), ["Shipped"])
    }

    func testAQuietWeekSaysSoRatherThanShowingEmptyLists() {
        strip("Touched today", quietDays: 0)
        let review = WeeklyReview.make(from: fetch(), now: now)
        XCTAssertTrue(review.isEmpty)
        XCTAssertEqual(review.needingAttention, 0)
    }

    /// Longest silence first: the thing ignored longest is the thing most likely forgotten.
    func testTheLongestSilenceComesFirst() {
        strip("Three weeks", quietDays: 21)
        strip("Two months", quietDays: 60)
        strip("Sixteen days", quietDays: 16)
        XCTAssertEqual(
            WeeklyReview.make(from: fetch(), now: now).stalled.map(\.title),
            ["Two months", "Three weeks", "Sixteen days"]
        )
    }

    func testHowLongIsSaidTheWaySomebodyWouldSayIt() {
        XCTAssertEqual(WeeklyReview.silence(of: strip("a", quietDays: 0), now: now), "today")
        XCTAssertEqual(WeeklyReview.silence(of: strip("b", quietDays: 1), now: now), "1 day")
        XCTAssertEqual(WeeklyReview.silence(of: strip("c", quietDays: 9), now: now), "9 days")
        XCTAssertEqual(WeeklyReview.silence(of: strip("d", quietDays: 21), now: now), "3 weeks")
        XCTAssertEqual(WeeklyReview.silence(of: strip("e", quietDays: 70), now: now), "2 months")
    }

    private func fetch() -> [TaskItem] {
        (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
    }
}
