import SwiftData
import XCTest
@testable import TaskStrips

final class BackupImportTests: XCTestCase {
    private func fixtureSummary() throws -> BackupImportSummary {
        let url = try XCTUnwrap(
            Bundle(for: BackupArchiveTests.self).url(forResource: "android_backup", withExtension: "zip")
        )
        let manifest = try BackupArchive.manifestData(inArchive: Data(contentsOf: url))
        return try BackupImport.parse(manifest: manifest)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func board(_ context: ModelContext) throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\TaskItem.orderIndex)]))
    }

    // MARK: - Parsing

    func testMapsEveryFieldOfAStrip() throws {
        let summary = try fixtureSummary()
        XCTAssertEqual(summary.version, 1)
        let passport = try XCTUnwrap(summary.tasks.first)

        XCTAssertEqual(passport.title, "Renew passport")
        XCTAssertEqual(passport.notes, "تجديد جواز السفر")
        XCTAssertTrue(passport.notesRtl)
        XCTAssertEqual(passport.priority, .urgent)
        XCTAssertEqual(passport.progress, 40)
        XCTAssertEqual(passport.orderIndex, 2)
        XCTAssertFalse(passport.isDone)
        XCTAssertFalse(passport.isArchived)
        XCTAssertNil(passport.completedAt)
        XCTAssertEqual(passport.tags, ["admin", "travel"])
        XCTAssertEqual(passport.contacts.map(\.name), ["Consulate"])
        XCTAssertEqual(passport.contacts.first?.email, "visa@example.com")
        XCTAssertEqual(passport.links.map(\.url), ["https://example.com/renew"])
        XCTAssertEqual(passport.links.first?.label, "Renewal portal")
        XCTAssertEqual(passport.actionLog.map(\.text), ["Booked appointment", "Paid fee"])
    }

    /// Android writes every timestamp as epoch milliseconds; reading them as seconds would land
    /// these dates in the year 58,000-odd without ever failing loudly.
    func testConvertsMillisecondTimestamps() throws {
        let passport = try XCTUnwrap(try fixtureSummary().tasks.first)
        XCTAssertEqual(passport.dueAt, Date(timeIntervalSince1970: 1_789_000_000))
        XCTAssertEqual(passport.createdAt, Date(timeIntervalSince1970: 1_786_000_000))
        XCTAssertEqual(passport.actionLog.first?.timestamp, Date(timeIntervalSince1970: 1_787_000_000))

        let flights = try XCTUnwrap(try fixtureSummary().tasks.dropFirst().first)
        XCTAssertEqual(flights.waitingOnSince, Date(timeIntervalSince1970: 1_787_200_000))
        XCTAssertEqual(flights.waitingOnName, "Travel desk")
        XCTAssertEqual(flights.waitingOnFollowUpDays, 3)
        XCTAssertNil(flights.dueAt)
    }

    func testCountsWhatItCannotImport() throws {
        let summary = try fixtureSummary()
        XCTAssertEqual(summary.attachmentCount, 3)  // 2 images + 1 document
        XCTAssertEqual(summary.reminderOnTaskCount, 1)

        let sections = Dictionary(uniqueKeysWithValues: summary.skippedSections.map { ($0.name, $0.count) })
        XCTAssertEqual(sections["notes"], 2)
        XCTAssertEqual(sections["standalone reminders"], 1)
        XCTAssertEqual(sections["storage items"], 3)
        // Empty sections aren't worth telling the user about.
        XCTAssertNil(sections["credentials"])
    }

    /// org.json's opt* accessors never throw on a missing or null field, and neither should this —
    /// one unexpected field shouldn't cost the user the whole import.
    func testParsesAStripWithNothingButATitle() throws {
        let manifest = Data(#"{"tasks":[{"title":"Bare"}]}"#.utf8)
        let summary = try BackupImport.parse(manifest: manifest)
        let task = try XCTUnwrap(summary.tasks.first)
        XCTAssertEqual(task.title, "Bare")
        XCTAssertEqual(task.priority, .normal)
        XCTAssertEqual(task.progress, 0)
        XCTAssertNil(task.dueAt)
        XCTAssertTrue(task.tags.isEmpty)
    }

    func testRejectsJSONWithNoTasksSection() {
        let manifest = Data(#"{"version":1,"notes":[]}"#.utf8)
        XCTAssertThrowsError(try BackupImport.parse(manifest: manifest))
    }

    func testClampsAnOutOfRangeProgress() throws {
        let manifest = Data(#"{"tasks":[{"title":"A","progress":140},{"title":"B","progress":-5}]}"#.utf8)
        let summary = try BackupImport.parse(manifest: manifest)
        XCTAssertEqual(summary.tasks.map(\.progress), [100, 0])
    }

    // MARK: - Applying

    func testRemapsBlockedByIndexToTheRealStripID() throws {
        let context = try makeContext()
        BackupImport.apply(try fixtureSummary().tasks, mode: .add, existing: [], context: context)

        let tasks = try board(context)
        let passport = try XCTUnwrap(tasks.first { $0.title == "Renew passport" })
        let flights = try XCTUnwrap(tasks.first { $0.title == "Book flights" })
        XCTAssertEqual(flights.blockedByID, passport.id)
        XCTAssertNil(passport.blockedByID)
    }

    /// The backup's array order is insertion order; its board order lives in each strip's own
    /// orderIndex, and that's what the board has to come back in.
    func testRebuildsBoardOrderFromTheBackupsOrderIndex() throws {
        let context = try makeContext()
        BackupImport.apply(try fixtureSummary().tasks, mode: .add, existing: [], context: context)
        XCTAssertEqual(try board(context).map(\.title), ["Book flights", "File expenses", "Renew passport"])
    }

    func testAddModeAppendsBelowWhatIsAlreadyOnTheBoard() throws {
        let context = try makeContext()
        let existing = [
            TaskItem(title: "Already here", orderIndex: 0),
            TaskItem(title: "Also here", orderIndex: 1),
        ]
        for task in existing { context.insert(task) }

        BackupImport.apply(try fixtureSummary().tasks, mode: .add, existing: existing, context: context)

        XCTAssertEqual(
            try board(context).map(\.title),
            ["Already here", "Also here", "Book flights", "File expenses", "Renew passport"]
        )
    }

    func testReplaceModeClearsTheBoardFirst() throws {
        let context = try makeContext()
        let existing = [TaskItem(title: "Already here", orderIndex: 0)]
        for task in existing { context.insert(task) }

        let imported = BackupImport.apply(
            try fixtureSummary().tasks, mode: .replace, existing: existing, context: context
        )

        XCTAssertEqual(imported, 3)
        XCTAssertEqual(try board(context).map(\.title), ["Book flights", "File expenses", "Renew passport"])
    }

    func testKeepsArchivedStripsArchived() throws {
        let context = try makeContext()
        BackupImport.apply(try fixtureSummary().tasks, mode: .add, existing: [], context: context)

        let expenses = try XCTUnwrap(try board(context).first { $0.title == "File expenses" })
        XCTAssertTrue(expenses.isArchived)
        XCTAssertTrue(expenses.isDone)
        XCTAssertEqual(expenses.completedAt, Date(timeIntervalSince1970: 1_787_900_000))
        XCTAssertEqual(expenses.priority, .low)
    }
}
