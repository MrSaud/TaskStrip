import XCTest
@testable import TaskStrips

/// The contract between the two apps for the board itself. Everything here has to hold identically
/// in Kotlin, because the phone and the Mac merge the same document independently and have to
/// reach the same answer without talking to each other.
final class SyncBoardDocumentTests: XCTestCase {

    private func task(_ id: String, title: String = "", notes: String = "", at updated: Int64,
                      deleted: Bool = false) -> SyncTaskRecord {
        SyncTaskRecord(id: id, updatedAt: updated, isDeleted: deleted, title: title, notes: notes)
    }

    private func reminder(_ id: String, text: String = "", at updated: Int64,
                          deleted: Bool = false) -> SyncReminderRecord {
        SyncReminderRecord(id: id, updatedAt: updated, isDeleted: deleted, text: text)
    }

    // MARK: - The file

    func testAStripSurvivesTheRoundTrip() throws {
        let original = SyncTaskRecord(
            id: "a", updatedAt: 1_787_000_000_000, title: "Renew the hangar insurance",
            notes: "Broker wants the valuation", notesRtl: true, priority: "URGENT",
            dueAt: 1_787_100_000_000, orderIndex: 3, progress: 40,
            blockedBySyncID: "b", waitingOnName: "Broker", waitingOnFollowUpDays: 5,
            repeatIntervalDays: 30, tags: ["finance", "admin"],
            links: [SyncLink(url: "https://example.test", label: "Policy")],
            actionLog: [SyncLogEntry(text: "Chased", timestamp: 12)],
            contacts: [SyncContact(name: "Sam", email: "s@example.test", phone: "1")],
            attachments: [SyncAttachment(hash: "abc123", name: "policy.pdf", kind: "document")],
            createdAt: 1_786_000_000_000
        )

        let read = SyncBoardDocument.tasks(from: try SyncBoardDocument.data(tasks: [original], reminders: []))

        XCTAssertEqual(read, [original])
    }

    func testAReminderSurvivesTheRoundTrip() throws {
        let original = SyncReminderRecord(
            id: "r", updatedAt: 5, text: "Car Maintenance", details: "Service due",
            triggerAt: 1_787_000_000_000, leadMinutesBefore: 60, repeatAmount: 1,
            repeatUnit: "YEARLY", tag: "Service", tagEmoji: "🔧", createdAt: 3
        )

        let read = SyncBoardDocument.reminders(from: try SyncBoardDocument.data(tasks: [], reminders: [original]))

        XCTAssertEqual(read, [original])
    }

    /// A missing due date must come back missing. Reading it as zero would invent 1970 as a
    /// deadline and put the strip permanently overdue on the other device.
    func testAnAbsentDateStaysAbsent() throws {
        let original = SyncTaskRecord(id: "a", updatedAt: 1, dueAt: nil, completedAt: nil)

        let read = SyncBoardDocument.tasks(from: try SyncBoardDocument.data(tasks: [original], reminders: []))

        XCTAssertNil(read.first?.dueAt)
        XCTAssertNil(read.first?.completedAt)
    }

    func testAnEntryWithNoIdIsDroppedRatherThanGivenOne() {
        let json = Data(#"{"version":1,"tasks":[{"id":"","title":"Ghost"},{"id":"a","title":"Real"}]}"#.utf8)

        XCTAssertEqual(SyncBoardDocument.tasks(from: json).map(\.title), ["Real"])
    }

    func testRubbishIsNoRowsRatherThanACrash() {
        XCTAssertEqual(SyncBoardDocument.tasks(from: Data("not json".utf8)).count, 0)
        XCTAssertEqual(SyncBoardDocument.reminders(from: Data("not json".utf8)).count, 0)
    }

    // MARK: - Merging

    func testTheNewerSideWins() {
        let merged = SyncBoardDocument.merge(
            local: [task("a", title: "Old", at: 1)],
            remote: [task("a", title: "New", at: 2)]
        )

        XCTAssertEqual(merged.map(\.title), ["New"])
    }

    /// A delete is a decision; a stale edit is not.
    func testADeleteOutranksAnEditStampedTheSame() {
        let merged = SyncBoardDocument.merge(
            local: [task("a", title: "Edited", at: 7)],
            remote: [task("a", at: 7, deleted: true)]
        )

        XCTAssertEqual(merged.first?.isDeleted, true)
    }

    /// The whole point of the tie-breaks: both devices must land on the same side no matter which
    /// order they merge in, or they hand each other opposite answers forever.
    func testMergingIsOrderIndependent() {
        let mine = [task("a", title: "Alpha", at: 4), task("b", title: "Beta", at: 9)]
        let theirs = [task("a", title: "Alef", at: 4), task("c", title: "Gamma", at: 1)]

        XCTAssertEqual(
            SyncBoardDocument.merge(local: mine, remote: theirs),
            SyncBoardDocument.merge(local: theirs, remote: mine)
        )
    }

    func testMergingRemindersIsOrderIndependentToo() {
        let mine = [reminder("a", text: "Alpha", at: 4)]
        let theirs = [reminder("a", text: "Alef", at: 4), reminder("b", text: "Beta", at: 2)]

        XCTAssertEqual(
            SyncBoardDocument.merge(local: mine, remote: theirs),
            SyncBoardDocument.merge(local: theirs, remote: mine)
        )
    }

    /// Running a sync twice must change nothing the second time.
    func testMergingIsIdempotent() {
        let mine = [task("a", title: "One", at: 3)]
        let theirs = [task("a", title: "Two", at: 5), task("b", title: "Other", at: 1)]

        let once = SyncBoardDocument.merge(local: mine, remote: theirs)

        XCTAssertEqual(SyncBoardDocument.merge(local: once, remote: theirs), once)
    }

    /// Bytes, not Swift's string ordering — Kotlin orders UTF-16 code units and Swift orders
    /// grapheme clusters, and a tie-break the two disagree about is worse than none.
    func testTheTieBreakComparesBytes() {
        XCTAssertTrue(SyncBoardDocument.isGreater("b", "a"))
        XCTAssertFalse(SyncBoardDocument.isGreater("a", "b"))
        XCTAssertTrue(SyncBoardDocument.isGreater("ab", "a"))
        XCTAssertFalse(SyncBoardDocument.isGreater("a", "a"))
        // Arabic: the same comparison both platforms can compute the same way.
        XCTAssertTrue(SyncBoardDocument.isGreater("ب", "ا"))
    }

    // MARK: - Files

    func testOnlyFilesALiveStripPointsAtAreKept() {
        let live = SyncTaskRecord(
            id: "a", updatedAt: 1,
            attachments: [SyncAttachment(hash: "keep", name: "a.jpg", kind: "image")]
        )
        let buried = SyncTaskRecord(
            id: "b", updatedAt: 1, isDeleted: true,
            attachments: [SyncAttachment(hash: "drop", name: "b.jpg", kind: "image")]
        )

        XCTAssertEqual(SyncBoardDocument.referencedHashes([live, buried]), ["keep"])
    }

    func testTombstonesAreBookkeepingNotRows() {
        let rows = [task("a", title: "Here", at: 1), task("b", at: 1, deleted: true)]

        XCTAssertEqual(SyncBoardDocument.visible(rows).map(\.title), ["Here"])
    }
}
