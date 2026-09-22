import SwiftData
import XCTest
@testable import TaskStrips

/// The board's rules, now shared by the Mac and the iPhone/iPad board.
final class StripActionsTests: XCTestCase {
    private var context: ModelContext!

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func strip(_ title: String, _ index: Int) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: index)
        context.insert(task)
        return task
    }

    func testCompletingAndReopeningFlipsDoneAndItsTime() {
        let task = strip("One", 0)

        XCTAssertEqual(StripActions.toggleDone(task, in: [task], context: context), .completed)
        XCTAssertTrue(task.isDone)
        XCTAssertNotNil(task.completedAt)

        XCTAssertEqual(StripActions.toggleDone(task, in: [task], context: context), .reopened)
        XCTAssertFalse(task.isDone)
        XCTAssertNil(task.completedAt)
    }

    func testABlockedStripCannotBeCompleted() {
        let blocker = strip("Blocker", 0)
        let task = strip("Waits", 1)
        task.blockedByID = blocker.id

        XCTAssertEqual(StripActions.toggleDone(task, in: [blocker, task], context: context), .blocked(by: blocker))
        XCTAssertFalse(task.isDone)
    }

    func testOnceItsBlockerIsDoneAStripCanBeCompleted() {
        let blocker = strip("Blocker", 0)
        blocker.isDone = true
        let task = strip("Waits", 1)
        task.blockedByID = blocker.id

        XCTAssertEqual(StripActions.toggleDone(task, in: [blocker, task], context: context), .completed)
    }

    func testCompletingARepeatingStripFilesTheNextAtTheBottom() throws {
        let other = strip("Other", 4)
        let task = strip("Weekly", 0)
        task.dueAt = .now
        task.repeatIntervalDays = 7

        StripActions.toggleDone(task, in: [other, task], context: context)

        let all = try context.fetch(FetchDescriptor<TaskItem>())
        let next = try XCTUnwrap(all.first { $0.title == "Weekly" && !$0.isDone })
        XCTAssertEqual(next.orderIndex, 5)
    }

    func testDeletingAStripFreesWhatItWasBlocking() throws {
        let blocker = strip("Blocker", 0)
        let task = strip("Waits", 1)
        task.blockedByID = blocker.id

        StripActions.delete(blocker, in: [blocker, task], context: context)

        XCTAssertNil(task.blockedByID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).map(\.title), ["Waits"])
    }

    func testUnarchivingPutsTheStripAtTheBottom() {
        let first = strip("First", 0)
        let second = strip("Second", 1)
        let archived = strip("Archived", 0)
        StripActions.archive(archived)
        XCTAssertTrue(archived.isArchived)

        StripActions.unarchive(archived, in: [first, second, archived])

        XCTAssertFalse(archived.isArchived)
        XCTAssertEqual(archived.orderIndex, 2)
    }
}
