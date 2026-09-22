import XCTest
@testable import TaskStrips

/// The folder route, against real files in a real directory. Unlike the Drive route, every part of
/// this is exercisable here — which is most of the argument for having it.
final class FolderSyncTransportTests: XCTestCase {

    private var folder: URL!
    private var transport: FolderSyncTransport!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "FolderSync-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        transport = FolderSyncTransport(folder: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func record(_ id: String, _ text: String, at seconds: TimeInterval) -> SyncNoteRecord {
        SyncNoteRecord(
            id: id, text: text,
            updatedAt: Date(timeIntervalSince1970: seconds), isDeleted: false
        )
    }

    private func write(_ notes: [SyncNoteRecord], named name: String) throws {
        try SyncNoteDocument.data(for: notes).write(to: folder.appending(path: name))
    }

    func testWhatIsSavedIsWhatComesBack() async throws {
        let notes = [record("a", "hello", at: 10), record("b", "there", at: 20)]

        try await transport.save(notes)

        // Bound first: XCTAssert's arguments are autoclosures, which cannot contain an await.
        let loaded = try await transport.load()
        XCTAssertEqual(loaded, SyncNoteDocument.sorted(notes))
    }

    func testTheFileIsTheOneBothAppsLookFor() async throws {
        try await transport.save([record("a", "x", at: 1)])

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: folder.appending(path: "sync_notes.json").path)
        )
    }

    /// An empty folder is not an emptied account. Reading it as anything else would let a machine
    /// that has never synced wipe one that has.
    func testAnEmptyFolderIsNoNotesRatherThanAnError() async throws {
        let loaded = try await transport.load()

        XCTAssertTrue(loaded.isEmpty)
    }

    /// Drive for desktop can leave a file present but not yet downloaded, and a folder can hold
    /// junk. Neither may read as "the other device deleted everything".
    func testAnUnreadableDocumentIsNoNotesRatherThanAnError() async throws {
        try Data("half a fi".utf8).write(to: folder.appending(path: "sync_notes.json"))

        let loaded = try await transport.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testTheFolderIsMadeIfItIsNotThereYet() async throws {
        let nested = folder.appending(path: "deeper/still", directoryHint: .isDirectory)

        try await FolderSyncTransport(folder: nested).save([record("a", "x", at: 1)])

        let loaded = try await FolderSyncTransport(folder: nested).load()
        XCTAssertEqual(loaded.map(\.text), ["x"])
    }

    // MARK: - What the daemon leaves behind

    /// The whole reason this transport is more than `Data(contentsOf:)`. Drive for desktop doesn't
    /// merge; it keeps both files. Reading only the plain name would silently lose the other
    /// device's edits, and nothing anywhere would say so.
    func testAConflictCopyIsMergedInRatherThanIgnored() async throws {
        try write([record("a", "from this Mac", at: 10)], named: "sync_notes.json")
        try write([record("b", "from the phone", at: 20)], named: "sync_notes (1).json")

        let loaded = try await transport.load()

        XCTAssertEqual(Set(loaded.map(\.text)), ["from this Mac", "from the phone"])
    }

    /// The decoration differs by client and by version, so the match is by shape.
    func testConflictCopiesAreRecognisedWhateverTheyAreCalled() throws {
        for name in [
            "sync_notes (1).json",
            "sync_notes (2).json",
            "sync_notes (conflicted copy 2026-08-30).json",
            "sync_notes-MacBook.json",
        ] {
            try write([], named: name)
        }
        try write([], named: "sync_notes.json")
        try write([], named: "something_else.json")
        try Data().write(to: folder.appending(path: "sync_notes (1).txt"))

        let found = Set(transport.conflictCopies().map(\.lastPathComponent))

        XCTAssertEqual(found, [
            "sync_notes (1).json",
            "sync_notes (2).json",
            "sync_notes (conflicted copy 2026-08-30).json",
            "sync_notes-MacBook.json",
        ])
    }

    /// Cleared only after their contents are in the real document — the merge is a union, so by
    /// the time save has written, nothing they held can have been dropped.
    func testConflictCopiesAreClearedOnceTheyHaveBeenAbsorbed() async throws {
        try write([record("a", "mine", at: 10)], named: "sync_notes.json")
        try write([record("b", "theirs", at: 20)], named: "sync_notes (1).json")

        let merged = try await transport.load()
        try await transport.save(merged)

        let reloaded = try await transport.load()
        XCTAssertTrue(transport.conflictCopies().isEmpty)
        XCTAssertEqual(Set(reloaded.map(\.text)), ["mine", "theirs"])
    }

    // MARK: - Through the sync

    func testAFullRoundTripThroughTheFolder() async throws {
        let phone = [record("a", "written on the phone", at: 20)]
        try write(phone, named: "sync_notes.json")

        let outcome = try await SyncNoteSync(transport: transport)
            .run(local: [record("b", "written on the Mac", at: 10)])

        let inTheFolder = try await transport.load()
        XCTAssertTrue(outcome.pushed)
        XCTAssertTrue(outcome.pulled)
        XCTAssertEqual(Set(inTheFolder.map(\.text)), [
            "written on the phone", "written on the Mac",
        ])
    }

    /// Nothing new means nothing written — otherwise merely opening the page would touch the file,
    /// and Drive for desktop would upload it, and the other machine would see a change that wasn't.
    func testASyncThatChangesNothingDoesNotTouchTheFile() async throws {
        let shared = [record("a", "settled", at: 10)]
        try await transport.save(shared)
        let stamp = try FileManager.default.attributesOfItem(
            atPath: transport.documentURL.path
        )[.modificationDate] as? Date

        let outcome = try await SyncNoteSync(transport: transport).run(local: shared)

        XCTAssertFalse(outcome.pushed)
        XCTAssertEqual(outcome.summary, "Already up to date.")
        let after = try FileManager.default.attributesOfItem(
            atPath: transport.documentURL.path
        )[.modificationDate] as? Date
        XCTAssertEqual(stamp, after)
    }

    /// The Mac and the phone reach the same folder by different routes, so what one writes the
    /// other has to be able to read — same file name, same bytes, same rules.
    func testWhatTheFolderHoldsIsTheSameDocumentDriveWouldHold() async throws {
        let notes = [record("a", "shared", at: 10)]
        try await transport.save(notes)

        let raw = try Data(contentsOf: transport.documentURL)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any])

        XCTAssertEqual(root["version"] as? Int, SyncNoteDocument.version)
        XCTAssertEqual(SyncNoteDocument.notes(from: raw), notes)
    }
}
