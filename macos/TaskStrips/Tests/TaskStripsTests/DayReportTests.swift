import SwiftData
import XCTest
@testable import TaskStrips

final class DayReportTests: XCTestCase {
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
    private func hours(_ count: Int) -> Date { calendar.date(byAdding: .hour, value: count, to: now)! }

    @discardableResult
    private func strip(_ title: String, due: Date? = nil) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: 0)
        task.dueAt = due
        context.insert(task)
        return task
    }

    private func report(_ tasks: [TaskItem], reminders: [Reminder] = []) -> DayReport {
        DayReport.make(tasks: tasks, reminders: reminders, on: now, since: days(-1), calendar: calendar)
    }

    func testItAsksForWhatIsLateAndWhatIsDue() {
        let late = strip("Late", due: days(-3))
        let today = strip("Today", due: hours(4))
        let later = strip("Later", due: days(4))

        let made = report([late, today, later])
        XCTAssertEqual(made.overdue, ["LATE"])
        XCTAssertEqual(made.dueToday, ["TODAY"])
        XCTAssertEqual(made.title, "2 things today")
        XCTAssertTrue(made.body.contains("Late: LATE"), made.body)
        XCTAssertTrue(made.body.contains("Due: TODAY"), made.body)
    }

    func testItSaysWhatWasDoneAndLoggedAndWorked() {
        let finished = strip("Finished")
        finished.isDone = true
        finished.completedAt = hours(-5)
        finished.actionLog = [TaskActionLogEntry(text: "Sent the form", timestamp: hours(-6))]
        finished.sessions = [TaskWorkSession(startedAt: hours(-7), endedAt: hours(-6))]

        let made = report([finished])
        XCTAssertEqual(made.done, ["FINISHED"])
        XCTAssertEqual(made.actions, ["Sent the form"])
        XCTAssertEqual(made.worked, 3600, accuracy: 1)
        XCTAssertTrue(made.body.contains("Worked: 1h 00m"), made.body)
    }

    /// Yesterday's report already said all this; today's shouldn't say it again.
    func testWhatHappenedBeforeTheLastReportIsNotRepeated() {
        let old = strip("Old news")
        old.isDone = true
        old.completedAt = days(-4)
        old.actionLog = [TaskActionLogEntry(text: "Ancient", timestamp: days(-4))]
        old.sessions = [TaskWorkSession(startedAt: days(-4), endedAt: days(-4).addingTimeInterval(3600))]

        let made = report([old])
        XCTAssertTrue(made.done.isEmpty)
        XCTAssertTrue(made.actions.isEmpty)
        XCTAssertEqual(made.worked, 0, accuracy: 0.1)
        XCTAssertTrue(made.isEmpty)
    }

    func testOnlyTodaysRemindersAreMentioned() {
        let today = Reminder(text: "Recycling", triggerAt: hours(3))
        let tomorrow = Reminder(text: "Rent", triggerAt: days(2))
        let made = report([], reminders: [today, tomorrow])
        XCTAssertEqual(made.reminders, ["Recycling"])
    }

    func testAStripWaitingForItsDayIsNotAskedFor() {
        let deferred = strip("Deferred", due: days(-1))
        deferred.deferUntil = days(6)
        XCTAssertTrue(report([deferred]).isEmpty)
    }

    /// A report that arrives every morning to say nothing is a report people turn off.
    func testAnEmptyDaySaysNothing() {
        XCTAssertTrue(report([]).isEmpty)
    }

    func testLongListsAreCutRatherThanScrolled() {
        let strips = (1...6).map { strip("Thing \($0)", due: days(-1)) }
        let body = report(strips).body
        XCTAssertTrue(body.contains("+ 3 more"), body)
    }

    func testAnHourReadsTheWayAnyoneSaysIt() {
        XCTAssertEqual(DigestPlan.hourLabel(8), "8am")
        XCTAssertEqual(DigestPlan.hourLabel(17), "5pm")
        XCTAssertEqual(DigestPlan.hourLabel(12), "noon")
        XCTAssertEqual(DigestPlan.hourLabel(0), "midnight")
    }

    func testTheReportCanBeSetToAnyOfTheOfferedHours() throws {
        for hour in DigestPlan.reportHours {
            let fireAt = try XCTUnwrap(DigestPlan.nextDaily(after: now, hour: hour, calendar: calendar))
            XCTAssertGreaterThan(fireAt, now)
            XCTAssertEqual(calendar.component(.hour, from: fireAt), hour)
        }
    }
}

final class StripNotificationTests: XCTestCase {
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func strip(_ title: String = "Something") -> TaskItem {
        let task = TaskItem(title: title, orderIndex: 0)
        context.insert(task)
        return task
    }

    func testAStripWithADueDateIsToldWhenItIsDue() {
        let task = strip()
        task.dueAt = now.addingTimeInterval(3600)
        XCTAssertEqual(ReminderPlan.dueDate(for: task, now: now), task.dueAt)
    }

    func testNothingIsAnnouncedForWorkThatIsPastDoneOrArchived() {
        let past = strip()
        past.dueAt = now.addingTimeInterval(-60)
        XCTAssertNil(ReminderPlan.dueDate(for: past, now: now))

        let done = strip()
        done.dueAt = now.addingTimeInterval(3600)
        done.isDone = true
        XCTAssertNil(ReminderPlan.dueDate(for: done, now: now))

        let archived = strip()
        archived.dueAt = now.addingTimeInterval(3600)
        archived.isArchived = true
        XCTAssertNil(ReminderPlan.dueDate(for: archived, now: now))

        XCTAssertNil(ReminderPlan.dueDate(for: strip(), now: now), "no due date, nothing to say")
    }

    func testADeferredStripSaysSoOnTheMorningItComesBack() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let task = strip()
        task.deferUntil = calendar.date(byAdding: .day, value: 3, to: now)!
        let fireAt = try XCTUnwrap(ReminderPlan.returnDate(for: task, now: now, calendar: calendar))

        XCTAssertEqual(calendar.component(.hour, from: fireAt), DigestPlan.dailyHour, "in the morning")
        XCTAssertEqual(
            calendar.startOfDay(for: fireAt),
            calendar.startOfDay(for: task.deferUntil!),
            "on the day it comes back"
        )
    }

    func testAStripThatIsNotDeferredHasNoReturnToAnnounce() {
        XCTAssertNil(ReminderPlan.returnDate(for: strip(), now: now))
    }

    /// Every alarm a strip can carry has its own name, or one would silently replace another.
    func testEachOfAStripsAlarmsIsItsOwn() {
        let id = UUID()
        let names = Set([
            id.uuidString,
            ReminderScheduler.followUpIdentifier(forTaskID: id),
            ReminderScheduler.dueIdentifier(forTaskID: id),
            ReminderScheduler.returnIdentifier(forTaskID: id),
        ])
        XCTAssertEqual(names.count, 4)
    }
}
