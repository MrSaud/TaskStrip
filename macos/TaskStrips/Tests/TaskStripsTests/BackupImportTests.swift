import SwiftData
import XCTest
@testable import TaskStrips

final class BackupImportTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots { try? FileManager.default.removeItem(at: root) }
        temporaryRoots = []
    }

    private func fixtureURL(_ name: String = "android_backup") throws -> URL {
        try XCTUnwrap(
            Bundle(for: BackupArchiveTests.self).url(forResource: name, withExtension: "zip")
        )
    }

    private func fixtureSummary() throws -> BackupImportSummary {
        let manifest = try BackupArchive.manifestData(inArchive: Data(contentsOf: try fixtureURL()))
        return try BackupImport.parse(manifest: manifest)
    }

    /// A store rooted in a temp directory, so nothing here can reach the real media folder.
    private func makeStore() throws -> AttachmentStore {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "import-media-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryRoots.append(root)
        return AttachmentStore(root: root)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, Note.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func board(_ context: ModelContext) throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\TaskItem.orderIndex)]))
    }

    private func scratchpad(_ context: ModelContext) throws -> [Note] {
        try context.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\Note.createdAt)]))
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
        XCTAssertEqual(passport.createdAt, Date(timeIntervalSince1970: 1_786_000_000))
        XCTAssertEqual(passport.actionLog.first?.timestamp, Date(timeIntervalSince1970: 1_787_000_000))

        let flights = try XCTUnwrap(try fixtureSummary().tasks.dropFirst().first)
        XCTAssertEqual(flights.waitingOnSince, Date(timeIntervalSince1970: 1_787_200_000))
        // dueAt has its own convention and its own tests below.
        XCTAssertEqual(flights.waitingOnName, "Travel desk")
        XCTAssertEqual(flights.waitingOnFollowUpDays, 3)
        XCTAssertNil(flights.dueAt)
    }

    func testCountsWhatItCannotImport() throws {
        let summary = try fixtureSummary()
        XCTAssertEqual(summary.attachmentCount, 3)  // 2 images + 1 document
        XCTAssertEqual(summary.reminderOnTaskCount, 1)

        let sections = Dictionary(uniqueKeysWithValues: summary.skippedSections.map { ($0.name, $0.count) })
        // Quick notes do come across now, so they're no longer on this list.
        XCTAssertNil(sections["notes"])
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

    // MARK: - Attachments

    func testCollectsTheFilesEachStripClaims() throws {
        let passport = try XCTUnwrap(try fixtureSummary().tasks.first)
        XCTAssertEqual(
            passport.attachments,
            [
                ImportedAttachment(kind: .image, path: "images/passport.jpg"),
                ImportedAttachment(kind: .image, path: "images/form.jpg"),
                ImportedAttachment(kind: .document, path: "documents/checklist.pdf"),
            ]
        )
        XCTAssertEqual(passport.attachmentCount, 3)
    }

    func testReferencedPathsAreWhatTheArchiveWillBeAskedFor() throws {
        XCTAssertEqual(
            try fixtureSummary().referencedAttachmentPaths,
            ["images/passport.jpg", "images/form.jpg", "documents/checklist.pdf"]
        )
    }

    func testRestoresTheFilesTheArchiveActuallyCarries() throws {
        let store = try makeStore()
        let summary = try fixtureSummary()

        let restored = try BackupImport.restoreMedia(
            fromArchiveAt: try fixtureURL(),
            paths: summary.referencedAttachmentPaths,
            into: store
        )

        XCTAssertEqual(restored, ["images/passport.jpg", "images/form.jpg"])
        let written = store.root.appending(path: "images/passport.jpg")
        XCTAssertEqual(Array(try Data(contentsOf: written).prefix(4)), [0xFF, 0xD8, 0xFF, 0xE0])
    }

    /// The manifest names documents/checklist.pdf and the archive doesn't carry it — which is a
    /// state a real backup can be in, so it mustn't throw.
    func testAFileTheArchiveDoesNotCarryIsSimplyNotRestored() throws {
        let store = try makeStore()
        let restored = try BackupImport.restoreMedia(
            fromArchiveAt: try fixtureURL(),
            paths: try fixtureSummary().referencedAttachmentPaths,
            into: store
        )
        XCTAssertFalse(restored.contains("documents/checklist.pdf"))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.root.appending(path: "documents/checklist.pdf").path
            )
        )
    }

    func testRestoresJustAsWellFromAZip64Archive() throws {
        let store = try makeStore()
        let restored = try BackupImport.restoreMedia(
            fromArchiveAt: try fixtureURL("android_backup_zip64"),
            paths: try fixtureSummary().referencedAttachmentPaths,
            into: store
        )
        XCTAssertEqual(restored, ["images/passport.jpg", "images/form.jpg"])
    }

    /// Only what the strips point at: an Android backup also carries sketches and storage-library
    /// files, and copying those in would grow the folder for nothing.
    func testIgnoresMediaNothingPointsAt() throws {
        let store = try makeStore()
        let restored = try BackupImport.restoreMedia(
            fromArchiveAt: try fixtureURL(),
            paths: ["images/form.jpg"],
            into: store
        )
        XCTAssertEqual(restored, ["images/form.jpg"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.root.appending(path: "images/passport.jpg").path
            )
        )
    }

    func testAppliedStripsCarryTheirAttachments() throws {
        let context = try makeContext()
        BackupImport.apply(try fixtureSummary().tasks, mode: .add, existing: [], context: context)

        let passport = try XCTUnwrap(try board(context).first { $0.title == "Renew passport" })
        XCTAssertEqual(passport.attachments.map(\.path), [
            "images/passport.jpg", "images/form.jpg", "documents/checklist.pdf",
        ])
        XCTAssertEqual(passport.attachments.map(\.kind), [.image, .image, .document])
    }

    /// A document is the only kind whose stored name means anything, so it keeps it; the rest sit
    /// under a uuid and get numbered per kind instead.
    func testAttachmentNamesReadWell() throws {
        let context = try makeContext()
        BackupImport.apply(try fixtureSummary().tasks, mode: .add, existing: [], context: context)

        let passport = try XCTUnwrap(try board(context).first { $0.title == "Renew passport" })
        XCTAssertEqual(passport.attachments.map(\.name), ["Image 1", "Image 2", "checklist.pdf"])
    }

    func testAStripWithNoFilesGetsNone() throws {
        let context = try makeContext()
        BackupImport.apply(try fixtureSummary().tasks, mode: .add, existing: [], context: context)

        let flights = try XCTUnwrap(try board(context).first { $0.title == "Book flights" })
        XCTAssertTrue(flights.attachments.isEmpty)
    }

    func testRestoringNothingIsNotAnError() throws {
        let store = try makeStore()
        XCTAssertEqual(
            try BackupImport.restoreMedia(fromArchiveAt: try fixtureURL(), paths: [], into: store),
            []
        )
    }

    // MARK: - Due dates
    //
    // The one field Android doesn't store as an instant. It's a wall clock pinned to UTC, shown
    // in UTC everywhere on the phone, so reading it as a real instant lands it on the Mac shifted
    // by the local offset — three hours late at UTC+3, which is where this backup came from.

    /// 1789000000000 ms is 2026-09-10 00:26:40 UTC. Whatever zone you're in, that wall clock is
    /// what the phone showed, so that's the wall clock the Mac has to show.
    ///
    /// The expected values are derived rather than written by hand — the first version of this
    /// test hardcoded a date I'd worked out wrong, and twelve assertions failed against perfectly
    /// good conversion code. Reading the wall clock back out of the source instant can't drift
    /// from it the way a typed-in constant can.
    func testADueDateKeepsTheWallClockThePhoneShowed() throws {
        let millis = 1_789_000_000_000.0

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let expected = utc.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date(timeIntervalSince1970: millis / 1000)
        )
        XCTAssertEqual(expected.day, 10, "sanity: the fixture's due date is 2026-09-10 00:26 UTC")
        XCTAssertEqual(expected.hour, 0)

        for identifier in ["Asia/Riyadh", "America/Los_Angeles", "UTC", "Asia/Kolkata"] {
            let zone = try XCTUnwrap(TimeZone(identifier: identifier))
            let converted = BackupImport.dueDate(fromAndroidWallClock: millis, in: zone)

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: converted)

            XCTAssertEqual(parts.year, expected.year, identifier)
            XCTAssertEqual(parts.month, expected.month, identifier)
            XCTAssertEqual(parts.day, expected.day, identifier)
            XCTAssertEqual(parts.hour, expected.hour, identifier)
            XCTAssertEqual(parts.minute, expected.minute, identifier)
        }
    }

    /// The bug this replaced: read as a plain instant, the due date is off by the local offset.
    func testADueDateIsNotJustTheRawInstant() throws {
        let millis = 1_789_000_000_000.0
        let riyadh = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))

        let converted = BackupImport.dueDate(fromAndroidWallClock: millis, in: riyadh)
        let raw = Date(timeIntervalSince1970: millis / 1000)

        XCTAssertEqual(
            converted.timeIntervalSince(raw), -3 * 3600, accuracy: 1,
            "UTC+3 means the real instant is three hours earlier than the naive reading"
        )
    }

    func testInUTCTheTwoReadingsAgree() throws {
        let millis = 1_789_000_000_000.0
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(
            BackupImport.dueDate(fromAndroidWallClock: millis, in: utc),
            Date(timeIntervalSince1970: millis / 1000)
        )
    }

    func testParsingAppliesTheConventionToTheFixture() throws {
        let riyadh = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        let manifest = try BackupArchive.manifestData(inArchive: Data(contentsOf: try fixtureURL()))
        let summary = try BackupImport.parse(manifest: manifest, timeZone: riyadh)

        let passport = try XCTUnwrap(summary.tasks.first)
        XCTAssertEqual(
            passport.dueAt,
            BackupImport.dueDate(fromAndroidWallClock: 1_789_000_000_000, in: riyadh)
        )
        // Everything else stays a straight instant.
        XCTAssertEqual(passport.createdAt, Date(timeIntervalSince1970: 1_786_000_000))
    }

    // MARK: - Quick notes

    func testReadsTheQuickNotesSection() throws {
        let summary = try fixtureSummary()
        XCTAssertEqual(summary.notes.count, 2)
        let packing = try XCTUnwrap(summary.notes.first)
        XCTAssertEqual(packing.text, "Packing list\n[ ] socks\n[x] adapter")
        // A note's createdAt is a real System.currentTimeMillis(), unlike a strip's dueAt.
        XCTAssertEqual(packing.createdAt, Date(timeIntervalSince1970: 1_787_500_000))
    }

    func testABackupWithNoNotesSectionImportsNone() throws {
        let summary = try BackupImport.parse(manifest: Data(#"{"tasks":[{"title":"Bare"}]}"#.utf8))
        XCTAssertTrue(summary.notes.isEmpty)
    }

    func testAddingNotesKeepsTheOnesAlreadyOnTheScratchpad() throws {
        let context = try makeContext()
        let existing = Note(text: "Mine", createdAt: Date(timeIntervalSince1970: 1_000_000))
        context.insert(existing)

        BackupImport.apply(
            notes: try fixtureSummary().notes,
            mode: .add,
            existing: [existing],
            context: context
        )

        XCTAssertEqual(try scratchpad(context).map(\.text).first, "Mine")
        XCTAssertEqual(try scratchpad(context).count, 3)
    }

    func testReplacingClearsTheScratchpadFirst() throws {
        let context = try makeContext()
        let existing = Note(text: "Mine")
        context.insert(existing)

        BackupImport.apply(
            notes: try fixtureSummary().notes,
            mode: .replace,
            existing: [existing],
            context: context
        )

        XCTAssertEqual(try scratchpad(context).map(\.text), ["Packing list\n[ ] socks\n[x] adapter", "Ideas"])
    }
}
