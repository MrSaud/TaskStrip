import SwiftData
import XCTest
@testable import TaskStrips

/// What survives the trip out and back, and what deliberately doesn't. Mirrors BoardRecordsTest.kt.
final class BoardRecordsTests: XCTestCase {

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, Note.self, StorageItem.self, Reminder.self, Credential.self,
            SyncNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func strip() -> TaskItem {
        let task = TaskItem(title: "Renew the hangar insurance", orderIndex: 3, priority: .urgent)
        task.notes = "Broker wants the valuation"
        task.notesRtl = true
        task.progress = 40
        task.tags = ["finance", "admin"]
        task.links = [TaskLink(url: "https://example.test", label: "Policy")]
        task.contacts = [TaskContact(name: "Sam", email: "s@example.test", phone: "1")]
        return task
    }

    func testAStripGoesOutAndComesBackTheSame() throws {
        let original = strip()
        let record = BoardRecords.record(for: original)

        let landed = TaskItem(title: "", orderIndex: 0)
        BoardRecords.apply(record, to: landed)

        XCTAssertEqual(landed.title, original.title)
        XCTAssertEqual(landed.notes, original.notes)
        XCTAssertEqual(landed.notesRtl, original.notesRtl)
        XCTAssertEqual(landed.priorityRaw, original.priorityRaw)
        XCTAssertEqual(landed.progress, original.progress)
        XCTAssertEqual(landed.tags, original.tags)
        XCTAssertEqual(landed.links.map(\.url), original.links.map(\.url))
        XCTAssertEqual(landed.contacts.map(\.name), original.contacts.map(\.name))
    }

    /// Milliseconds are what Android writes everywhere, so both sides have to read each other's
    /// numbers without a second thought.
    func testDatesCrossAsMillisecondsAndComeBackIntact() {
        let when = Date(timeIntervalSince1970: 1_787_000_000.123)

        XCTAssertEqual(BoardRecords.millis(when), 1_787_000_000_123)
        XCTAssertEqual(
            BoardRecords.date(BoardRecords.millis(when)).timeIntervalSince1970,
            when.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testABlockerTravelsAsTheOtherStripsSharedID() {
        let blocked = strip()
        let blockerID = UUID()
        blocked.blockedByID = blockerID

        let record = BoardRecords.record(for: blocked, syncIDOfTask: { $0 == blockerID ? "strip-b" : nil })

        XCTAssertEqual(record.blockedBySyncID, "strip-b")
    }

    /// A blocker whose row has gone travels as nothing rather than as a made-up id.
    func testABlockerWhoseRowHasGoneTravelsAsNothing() {
        let blocked = strip()
        blocked.blockedByID = UUID()

        XCTAssertNil(BoardRecords.record(for: blocked, syncIDOfTask: { _ in nil }).blockedBySyncID)
    }

    func testAnArrivingBlockerBecomesThisMachinesOwnID() {
        var record = BoardRecords.record(for: strip())
        record.blockedBySyncID = "strip-b"
        let mine = UUID()
        let landed = strip()

        BoardRecords.apply(record, to: landed, localIDOfSyncID: { $0 == "strip-b" ? mine : nil })

        XCTAssertEqual(landed.blockedByID, mine)
    }

    /// The reason folding beats rebuilding: a record names files by hash, not by where this
    /// machine keeps them.
    func testArrivingOverAnExistingStripKeepsThisMachinesOwnFiles() {
        let here = strip()
        here.attachments = [TaskAttachment(kind: .image, path: "media/photo1.jpg", name: "photo1.jpg")]
        var arriving = BoardRecords.record(for: strip())
        arriving.title = "Renamed elsewhere"

        BoardRecords.apply(arriving, to: here)

        XCTAssertEqual(here.title, "Renamed elsewhere")
        XCTAssertEqual(here.attachments.map(\.path), ["media/photo1.jpg"])
    }

    /// A strip from a newer version of the app should be worth less, not fatal.
    func testAnUnknownPriorityFallsBackRatherThanThrowing() {
        var arriving = BoardRecords.record(for: strip())
        arriving.priority = "CATASTROPHIC"
        let landed = strip()

        BoardRecords.apply(arriving, to: landed)

        XCTAssertEqual(landed.priorityRaw, Priority.normal.rawValue)
    }

    /// A strip this machine has never seen keeps the shared id, which is what makes the next sync
    /// recognise it rather than send it back as something new.
    func testANewStripKeepsTheSharedID() {
        let id = UUID()
        var record = BoardRecords.record(for: strip())
        record.id = id.uuidString

        XCTAssertEqual(BoardRecords.newTask(from: record)?.id, id)
    }

    func testARecordWithAnUnreadableIDMakesNothing() {
        var record = BoardRecords.record(for: strip())
        record.id = "not-a-uuid"

        XCTAssertNil(BoardRecords.newTask(from: record))
    }

    /// A record names a file by hash, never by where this machine keeps it — overwriting the path
    /// would leave the item listed and no longer openable.
    func testAnArrivingLibraryItemLeavesThisMachinesPathAlone() {
        let here = StorageItem(name: "Policy.pdf", path: "library/policy.pdf", type: .document)
        var arriving = BoardRecords.record(for: here, hash: "abc")
        arriving.name = "Policy 2026.pdf"

        BoardRecords.apply(arriving, to: here)

        XCTAssertEqual(here.name, "Policy 2026.pdf")
        XCTAssertEqual(here.path, "library/policy.pdf")
    }
}
