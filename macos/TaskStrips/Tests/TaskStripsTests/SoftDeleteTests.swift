import SwiftData
import XCTest
@testable import TaskStrips

/// Proves the tombstone actually hides things, against a real store.
///
/// Worth doing rather than assuming, for one specific reason: SwiftData's own PersistentModel also
/// has an `isDeleted`. A stored property of that name shadows it, and the two disagree: a
/// #Predicate binds to ours while plain Swift `model.isDeleted` reads theirs. This test caught
/// exactly that, which is why the flag is called `isTombstoned` now.
final class SoftDeleteTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, Note.self, StorageItem.self, Reminder.self, Credential.self,
            SyncNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testATombstonedStripIsHiddenFromTheQueryTheBoardUses() throws {
        let context = try makeContext()
        let alive = TaskItem(title: "Alive", orderIndex: 0)
        let doomed = TaskItem(title: "Doomed", orderIndex: 1)
        context.insert(alive)
        context.insert(doomed)
        try context.save()

        context.tombstone(doomed)
        try context.save()

        let visible = try context.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isTombstoned })
        )

        XCTAssertEqual(visible.map(\.title), ["Alive"])
    }

    /// The row has to survive, or the delete can't reach the other device.
    func testTheRowSurvivesAndSaysItIsGone() throws {
        let context = try makeContext()
        let doomed = TaskItem(title: "Doomed", orderIndex: 0)
        context.insert(doomed)
        try context.save()
        let filedAt = doomed.lastEditedAt

        context.tombstone(doomed)
        try context.save()

        let everything = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(everything.count, 1)
        XCTAssertTrue(everything[0].isTombstoned)
        // Stamped, so the other device can tell this happened after whatever it last saw.
        XCTAssertGreaterThanOrEqual(everything[0].lastEditedAt, filedAt)
    }

    func testTheSameHoldsForReminders() throws {
        let context = try makeContext()
        let alive = Reminder(text: "Alive", triggerAt: .now)
        let doomed = Reminder(text: "Doomed", triggerAt: .now)
        context.insert(alive)
        context.insert(doomed)
        try context.save()

        context.tombstone(doomed)
        try context.save()

        let visible = try context.fetch(
            FetchDescriptor<Reminder>(predicate: #Predicate { !$0.isTombstoned })
        )

        XCTAssertEqual(visible.map(\.text), ["Alive"])
    }
}
