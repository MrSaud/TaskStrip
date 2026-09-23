import SwiftData
import XCTest
@testable import TaskStrips

final class StripCalendarPlanTests: XCTestCase {
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)   // 10:40 UTC on a Sunday
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

    private func strip(_ title: String = "Renew the passport", due: Date? = nil) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: 0)
        task.dueAt = due
        context.insert(task)
        return task
    }

    func testTheBlockEndsWhenTheStripIsDue() {
        let due = now.addingTimeInterval(5 * 3600)
        let start = StripCalendarPlan.start(for: strip(due: due), now: now, calendar: calendar)
        XCTAssertEqual(start, due.addingTimeInterval(-StripCalendarPlan.defaultDuration))
    }

    /// A block you can't attend is a lie on the calendar.
    func testItIsNeverBlockedInThePast() {
        let soon = now.addingTimeInterval(600)
        let start = StripCalendarPlan.start(for: strip(due: soon), now: now, calendar: calendar)
        XCTAssertGreaterThan(start, now)
    }

    func testWithNoDueDateItTakesTheNextHour() {
        let start = StripCalendarPlan.start(for: strip(), now: now, calendar: calendar)
        XCTAssertGreaterThan(start, now)
        let parts = calendar.dateComponents([.minute, .second], from: start)
        XCTAssertEqual(parts.minute, 0, "on the hour")
        XCTAssertEqual(parts.second, 0)
        XCTAssertLessThanOrEqual(start.timeIntervalSince(now), 3600)
    }

    func testTheEventIsCalledWhatTheStripIsCalled() {
        XCTAssertEqual(StripCalendarPlan.title(for: strip()), "Renew the passport")
        XCTAssertEqual(StripCalendarPlan.title(for: strip("")), "Task Strips")
    }

    func testTheEventCarriesTheNotesAndWhatIsStillToDo() {
        let task = strip()
        task.notes = "Photos are in the drawer."
        task.checklist = [
            TaskChecklistItem(text: "Photos", isDone: true),
            TaskChecklistItem(text: "Form", isDone: false),
        ]
        let notes = StripCalendarPlan.notes(for: task)

        XCTAssertTrue(notes.contains("Photos are in the drawer."), notes)
        XCTAssertTrue(notes.contains("• Form"), notes)
        XCTAssertFalse(notes.contains("• Photos"), "a step that's done isn't still to do")
        XCTAssertTrue(notes.hasSuffix("— Task Strips"), notes)
    }

    func testAnEmptyStripStillSaysWhereItCameFrom() {
        XCTAssertEqual(StripCalendarPlan.notes(for: strip()), "\n— Task Strips")
    }
}
