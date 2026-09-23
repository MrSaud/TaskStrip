import SwiftData
import XCTest
@testable import TaskStrips

final class DayPlanTests: XCTestCase {
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func days(_ count: Int) -> Date { calendar.date(byAdding: .day, value: count, to: now)! }

    @discardableResult
    private func strip(_ title: String, due: Date? = nil, done: Bool = false, archived: Bool = false) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: 0)
        task.dueAt = due
        task.isDone = done
        task.isArchived = archived
        context.insert(task)
        return task
    }

    private func plan(_ tasks: [TaskItem], reminders: [Reminder] = []) -> DayPlan {
        DayPlan.make(tasks: tasks, reminders: reminders, now: now, calendar: calendar)
    }

    func testTheDayIsLateWorkThenTodaysWork() {
        let late = strip("Late", due: days(-2))
        let today = strip("Today", due: now)
        let later = strip("Later", due: days(3))

        let day = plan([late, today, later])
        XCTAssertEqual(day.overdue.map(\.title), ["Late"])
        XCTAssertEqual(day.due.map(\.title), ["Today"])
        XCTAssertFalse(day.isEmpty)
        XCTAssertEqual(day.count, 2)
        XCTAssertTrue(day.overdue.allSatisfy { !$0.isDone })
        XCTAssertFalse(day.due.contains { $0.title == "Later" })
    }

    func testWhatIsDoneOrArchivedIsNotAskingForAnything() {
        let done = strip("Done", due: days(-1), done: true)
        let archived = strip("Archived", due: days(-1), archived: true)
        XCTAssertTrue(plan([done, archived]).isEmpty)
    }

    func testAStripWaitingForItsDayIsNotTodaysProblem() {
        let deferred = strip("Deferred", due: days(-1))
        deferred.deferUntil = days(5)
        XCTAssertTrue(plan([deferred]).isEmpty)
    }

    func testTheDayItComesBackItIsOnTheList() {
        let returning = strip("Back today")
        returning.deferUntil = now
        let day = plan([returning])
        XCTAssertEqual(day.returning.map(\.title), ["Back today"])
    }

    func testSomeoneIsChasedWhenTheFollowUpComesRound() {
        let waiting = strip("Waiting on Faisal")
        waiting.waitingOnName = "Faisal"
        waiting.waitingOnSince = days(-5)
        waiting.waitingOnFollowUpDays = 3

        let notYet = strip("Waiting on Sara")
        notYet.waitingOnName = "Sara"
        notYet.waitingOnSince = days(-1)
        notYet.waitingOnFollowUpDays = 7

        let day = plan([waiting, notYet])
        XCTAssertEqual(day.chase.map(\.title), ["Waiting on Faisal"])
    }

    func testAWaitingStripWithNoFollowUpAgreedIsNeverChased() {
        let waiting = strip("Waiting")
        waiting.waitingOnName = "Someone"
        waiting.waitingOnSince = days(-30)
        XCTAssertTrue(plan([waiting]).chase.isEmpty)
    }

    func testOnlyTodaysRemindersAreOnTheList() {
        let today = Reminder(text: "Today", triggerAt: calendar.date(byAdding: .hour, value: 2, to: now)!)
        let tomorrow = Reminder(text: "Tomorrow", triggerAt: days(1))
        let finished = Reminder(text: "Done", triggerAt: now, isDone: true)

        let day = plan([], reminders: [tomorrow, today, finished])
        XCTAssertEqual(day.reminders.map(\.text), ["Today"])
    }

    func testTheLateWorkIsInTheOrderItFellDue() {
        let older = strip("Older", due: days(-9))
        let newer = strip("Newer", due: days(-2))
        XCTAssertEqual(plan([newer, older]).overdue.map(\.title), ["Older", "Newer"])
    }

    func testAnEmptyDayIsEmpty() {
        XCTAssertTrue(plan([]).isEmpty)
        XCTAssertEqual(plan([]).count, 0)
    }
}
