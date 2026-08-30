import SwiftData
import XCTest
@testable import TaskStrips

final class ReminderPlanTests: XCTestCase {
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: TaskItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    private func makeTask(
        dueIn hours: Double? = 24,
        minutesBefore: Int? = 30,
        repeatDays: Int? = nil
    ) -> TaskItem {
        let task = TaskItem(title: "Renew passport", orderIndex: 0)
        task.dueAt = hours.map { now.addingTimeInterval($0 * 3600) }
        task.reminderMinutesBefore = minutesBefore
        task.repeatIntervalDays = repeatDays
        context.insert(task)
        return task
    }

    // MARK: - When a reminder fires

    func testFiresTheLeadTimeBeforeTheDueDate() {
        let task = makeTask(dueIn: 24, minutesBefore: 30)
        XCTAssertEqual(
            ReminderPlan.fireDate(for: task, now: now),
            now.addingTimeInterval(24 * 3600 - 30 * 60)
        )
    }

    func testNoDueDateMeansNoReminder() {
        XCTAssertNil(ReminderPlan.fireDate(for: makeTask(dueIn: nil), now: now))
    }

    func testNoLeadTimeMeansNoReminder() {
        XCTAssertNil(ReminderPlan.fireDate(for: makeTask(minutesBefore: nil), now: now))
    }

    func testADoneStripDoesNotRemind() {
        let task = makeTask()
        task.isDone = true
        XCTAssertNil(ReminderPlan.fireDate(for: task, now: now))
    }

    func testAnArchivedStripDoesNotRemind() {
        let task = makeTask()
        task.isArchived = true
        XCTAssertNil(ReminderPlan.fireDate(for: task, now: now))
    }

    /// The case that matters on import: a backup is full of due dates in the past, and none of
    /// them should announce themselves the moment they arrive.
    func testAMomentAlreadyPastDoesNotRemind() {
        XCTAssertNil(ReminderPlan.fireDate(for: makeTask(dueIn: -48), now: now))
    }

    /// Due soon enough that the lead time has already elapsed, though the strip isn't overdue.
    func testALeadTimeThatHasAlreadyElapsedDoesNotRemind() {
        let task = makeTask(dueIn: 0.25, minutesBefore: 30)
        XCTAssertNil(ReminderPlan.fireDate(for: task, now: now))
    }

    // MARK: - What completing a repeating strip spawns

    func testANonRepeatingStripSpawnsNothing() {
        XCTAssertNil(ReminderPlan.nextOccurrence(completing: makeTask(), orderIndex: 5))
    }

    func testARepeatWithNoDueDateSpawnsNothing() {
        let task = makeTask(dueIn: nil, repeatDays: 7)
        XCTAssertNil(ReminderPlan.nextOccurrence(completing: task, orderIndex: 5))
    }

    func testTheNextOccurrenceIsTheIntervalLater() throws {
        let task = makeTask(dueIn: 24, repeatDays: 7)
        let next = try XCTUnwrap(ReminderPlan.nextOccurrence(completing: task, orderIndex: 5))

        XCTAssertEqual(next.dueAt, task.dueAt?.addingTimeInterval(7 * 24 * 3600))
        XCTAssertEqual(next.orderIndex, 5)
        XCTAssertFalse(next.isDone)
    }

    func testTheNextOccurrenceCarriesWhatDescribesTheWork() throws {
        let task = makeTask(dueIn: 24, minutesBefore: 15, repeatDays: 30)
        task.notes = "bring both forms"
        task.notesRtl = true
        task.tags = ["admin", "travel"]
        task.priority = .urgent

        let next = try XCTUnwrap(ReminderPlan.nextOccurrence(completing: task, orderIndex: 1))
        XCTAssertEqual(next.title, "Renew passport")
        XCTAssertEqual(next.notes, "bring both forms")
        XCTAssertTrue(next.notesRtl)
        XCTAssertEqual(next.tags, ["admin", "travel"])
        XCTAssertEqual(next.priority, .urgent)
        XCTAssertEqual(next.reminderMinutesBefore, 15)
        XCTAssertEqual(next.repeatIntervalDays, 30, "so it keeps repeating")
    }

    /// Progress, files, contacts, links and the log belong to the occurrence that just finished.
    func testTheNextOccurrenceStartsClean() throws {
        let task = makeTask(dueIn: 24, repeatDays: 7)
        task.progress = 80
        task.attachments = [TaskAttachment(kind: .image, path: "images/a.jpg", name: "Image 1")]
        task.contacts = [TaskContact(name: "Consulate")]
        task.links = [TaskLink(url: "https://example.com", label: "Portal")]
        task.actionLog = [TaskActionLogEntry(text: "Paid fee")]
        task.waitingOnName = "Travel desk"

        let next = try XCTUnwrap(ReminderPlan.nextOccurrence(completing: task, orderIndex: 1))
        XCTAssertEqual(next.progress, 0)
        XCTAssertTrue(next.attachments.isEmpty)
        XCTAssertTrue(next.contacts.isEmpty)
        XCTAssertTrue(next.links.isEmpty)
        XCTAssertTrue(next.actionLog.isEmpty)
        XCTAssertTrue(next.waitingOnName.isEmpty)
    }

    func testAZeroOrNegativeIntervalSpawnsNothing() {
        for interval in [0, -7] {
            let task = makeTask(dueIn: 24, repeatDays: interval)
            XCTAssertNil(
                ReminderPlan.nextOccurrence(completing: task, orderIndex: 1),
                "interval \(interval) would never move the due date forward"
            )
        }
    }

    // MARK: - Chasing whoever the strip is waiting on

    private func delegated(
        since: Date?,
        days: Int?,
        name: String = "Travel desk",
        done: Bool = false,
        archived: Bool = false
    ) -> TaskItem {
        let task = TaskItem(title: "Visa application", orderIndex: 0)
        task.waitingOnName = name
        task.waitingOnSince = since
        task.waitingOnFollowUpDays = days
        task.isDone = done
        task.isArchived = archived
        return task
    }

    /// Counted from when the waiting started, not from a due date: "handed over Tuesday, nudge me
    /// Friday" is what the field means.
    func testTheFollowUpIsCountedFromWhenTheWaitingStarted() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let task = delegated(since: now, days: 3)

        XCTAssertEqual(
            ReminderPlan.followUpDate(for: task, now: now),
            now.addingTimeInterval(3 * 24 * 60 * 60)
        )
    }

    func testAFollowUpNeedsSomeoneToChaseAndADateToCountFrom() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)

        XCTAssertNil(ReminderPlan.followUpDate(for: delegated(since: nil, days: 3), now: now))
        XCTAssertNil(ReminderPlan.followUpDate(for: delegated(since: now, days: nil), now: now))
        XCTAssertNil(ReminderPlan.followUpDate(for: delegated(since: now, days: 3, name: ""), now: now))
        XCTAssertNil(
            ReminderPlan.followUpDate(for: delegated(since: now, days: 3, name: "   "), now: now),
            "a name of spaces is nobody to chase"
        )
    }

    func testAFinishedOrArchivedStripIsNotChased() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        XCTAssertNil(ReminderPlan.followUpDate(for: delegated(since: now, days: 3, done: true), now: now))
        XCTAssertNil(ReminderPlan.followUpDate(for: delegated(since: now, days: 3, archived: true), now: now))
    }

    /// An import arrives full of waiting that started weeks ago; none of it should announce
    /// itself on arrival.
    func testAFollowUpThatIsAlreadyOverdueDoesNotFire() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let task = delegated(since: now.addingTimeInterval(-10 * 24 * 60 * 60), days: 3)
        XCTAssertNil(ReminderPlan.followUpDate(for: task, now: now))
    }

    /// The two alarms a strip can have are separate: waiting on someone says nothing about when
    /// the work is due.
    func testTheFollowUpIsIndependentOfTheDueDateReminder() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let task = delegated(since: now, days: 2)
        task.dueAt = now.addingTimeInterval(30 * 24 * 60 * 60)
        task.reminderMinutesBefore = 60

        XCTAssertNotNil(ReminderPlan.followUpDate(for: task, now: now))
        XCTAssertNotNil(ReminderPlan.fireDate(for: task, now: now))
        XCTAssertNotEqual(ReminderPlan.followUpDate(for: task, now: now), ReminderPlan.fireDate(for: task, now: now))
    }

    /// Two alarms in one flat namespace, so they can't share an identifier.
    func testAStripsTwoAlarmsAreNamedApart() {
        let id = UUID()
        XCTAssertNotEqual(ReminderScheduler.followUpIdentifier(forTaskID: id), id.uuidString)
        XCTAssertTrue(ReminderScheduler.followUpIdentifier(forTaskID: id).contains(id.uuidString))
    }
}
