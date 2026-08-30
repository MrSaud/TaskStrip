import XCTest
@testable import TaskStrips

/// The contract between the two apps. Everything here has to hold identically in Kotlin, because
/// the phone and the Mac merge the same document independently and have to reach the same answer.
final class SyncNoteDocumentTests: XCTestCase {

    private func note(
        _ id: String,
        title: String = "",
        text: String = "",
        at seconds: TimeInterval,
        deleted: Bool = false
    ) -> SyncNoteRecord {
        SyncNoteRecord(
            id: id,
            title: title,
            text: text,
            updatedAt: Date(timeIntervalSince1970: seconds),
            isDeleted: deleted
        )
    }

    // MARK: - The file

    func testANoteSurvivesTheRoundTrip() throws {
        let original = note("a", title: "Groceries", text: "milk\nbread", at: 1_787_000_000)

        let read = SyncNoteDocument.notes(from: try SyncNoteDocument.data(for: [original]))

        XCTAssertEqual(read, [original])
    }

    /// Android writes every instant in this app as epoch milliseconds; a document it can't read is
    /// no use at all.
    func testTimesAreWrittenAsMilliseconds() throws {
        let data = try SyncNoteDocument.data(for: [note("a", at: 1_787_000_000)])
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let notes = try XCTUnwrap(root["notes"] as? [[String: Any]])

        XCTAssertEqual(notes[0]["updatedAt"] as? Int, 1_787_000_000_000)
        XCTAssertEqual(root["version"] as? Int, 1)
    }

    func testATombstoneIsWrittenOutAsOne() throws {
        let data = try SyncNoteDocument.data(for: [note("a", at: 1, deleted: true)])
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let notes = try XCTUnwrap(root["notes"] as? [[String: Any]])

        XCTAssertEqual(notes[0]["deleted"] as? Bool, true)
    }

    /// A half-written or corrupt document in Drive must not be able to empty this machine. Reading
    /// it as "no notes" means the merge adds nothing and the next upload replaces it.
    func testNonsenseReadsAsNoNotesRatherThanThrowing() {
        XCTAssertTrue(SyncNoteDocument.notes(from: Data("not json".utf8)).isEmpty)
        XCTAssertTrue(SyncNoteDocument.notes(from: Data()).isEmpty)
        XCTAssertTrue(SyncNoteDocument.notes(from: Data(#"{"notes":"nope"}"#.utf8)).isEmpty)
    }

    /// An entry with no id can't be merged against anything, so it's dropped rather than given a
    /// fresh id and duplicated on every sync.
    func testAnEntryWithNoIDIsSkipped() {
        let data = Data(#"{"version":1,"notes":[{"text":"orphan"},{"id":"a","text":"kept"}]}"#.utf8)

        XCTAssertEqual(SyncNoteDocument.notes(from: data).map(\.id), ["a"])
    }

    // MARK: - Merging

    func testEachSideKeepsWhatTheOtherHasNotSeen() {
        let merged = SyncNoteDocument.merge(
            local: [note("a", text: "mine", at: 10)],
            remote: [note("b", text: "theirs", at: 20)]
        )

        XCTAssertEqual(merged.map(\.id), ["b", "a"])
    }

    func testTheNewerEditWins() {
        let merged = SyncNoteDocument.merge(
            local: [note("a", text: "old", at: 10)],
            remote: [note("a", text: "new", at: 20)]
        )

        XCTAssertEqual(merged.map(\.text), ["new"])
    }

    func testTheNewerEditWinsWhicheverSideItIsOn() {
        let merged = SyncNoteDocument.merge(
            local: [note("a", text: "new", at: 20)],
            remote: [note("a", text: "old", at: 10)]
        )

        XCTAssertEqual(merged.map(\.text), ["new"])
    }

    /// The whole reason tombstones exist: without one, the device that still has the note would
    /// hand it straight back on the next sync.
    func testADeleteTravelsAndDoesNotComeBack() {
        let deletedHere = note("a", at: 20, deleted: true)
        let stillThere = note("a", text: "zombie", at: 10)

        let merged = SyncNoteDocument.merge(local: [deletedHere], remote: [stillThere])

        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].isDeleted)
        XCTAssertTrue(SyncNoteDocument.visible(merged).isEmpty)
    }

    /// An edit made after the delete is a decision too, and a later one.
    func testANoteEditedAfterItWasDeletedComesBack() {
        let merged = SyncNoteDocument.merge(
            local: [note("a", at: 10, deleted: true)],
            remote: [note("a", text: "back", at: 20)]
        )

        XCTAssertEqual(SyncNoteDocument.visible(merged).map(\.text), ["back"])
    }

    // MARK: - Both devices reaching the same answer

    /// The property the whole design rests on: neither device knows who synced first, so merging
    /// in either order has to give the same result.
    func testMergingIsTheSameInEitherOrder() {
        let local = [
            note("a", text: "local a", at: 30),
            note("b", text: "local b", at: 10),
            note("c", text: "only local", at: 5),
        ]
        let remote = [
            note("a", text: "remote a", at: 20),
            note("b", text: "remote b", at: 40),
            note("d", text: "only remote", at: 7, deleted: true),
        ]

        XCTAssertEqual(
            SyncNoteDocument.merge(local: local, remote: remote),
            SyncNoteDocument.merge(local: remote, remote: local)
        )
    }

    /// Same-millisecond edits on both devices are the one case a single shared document can't
    /// reconcile properly. It must at least be decided the same way on both, or they would swap
    /// answers forever.
    func testASimultaneousEditIsDecidedTheSameWayOnBothDevices() {
        let a = note("x", text: "aaa", at: 100)
        let b = note("x", text: "bbb", at: 100)

        XCTAssertEqual(SyncNoteDocument.winner(a, b), SyncNoteDocument.winner(b, a))
        XCTAssertEqual(SyncNoteDocument.winner(a, b).text, "bbb")
    }

    func testASimultaneousDeleteBeatsASimultaneousEdit() {
        let edited = note("x", text: "still here", at: 100)
        let deleted = note("x", at: 100, deleted: true)

        XCTAssertEqual(SyncNoteDocument.winner(edited, deleted), deleted)
        XCTAssertEqual(SyncNoteDocument.winner(deleted, edited), deleted)
    }

    /// Syncing twice with nothing happening in between must not keep changing the document, or
    /// every sync would push and the two devices would ping-pong.
    func testMergingAnAlreadyMergedDocumentChangesNothing() {
        let local = [note("a", text: "one", at: 10), note("b", text: "two", at: 20)]
        let remote = [note("a", text: "one edited", at: 30)]

        let once = SyncNoteDocument.merge(local: local, remote: remote)
        let twice = SyncNoteDocument.merge(local: once, remote: once)

        XCTAssertEqual(once, twice)
    }

    // MARK: - What a note is called

    func testANoteWithNoTitleIsNamedByItsFirstRealLine() {
        XCTAssertEqual(note("a", text: "\n\n  Buy milk\nand bread", at: 1).displayTitle, "Buy milk")
    }

    func testATitleWinsOverTheText() {
        XCTAssertEqual(note("a", title: "Shopping", text: "Buy milk", at: 1).displayTitle, "Shopping")
    }

    func testANoteWithNothingInItIsStillCalledSomething() {
        XCTAssertEqual(note("a", text: "   \n  ", at: 1).displayTitle, "Untitled")
    }

    func testALongFirstLineIsCutRatherThanFillingTheList() {
        let long = String(repeating: "x", count: 200)

        XCTAssertEqual(note("a", text: long, at: 1).displayTitle.count, 80)
    }
}
