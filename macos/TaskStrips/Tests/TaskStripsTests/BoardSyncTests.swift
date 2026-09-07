import XCTest
@testable import TaskStrips

/// The round trip, against a transport that remembers the order it was asked to do things.
///
/// Most of what matters here is ordering. Every individual decision is tested elsewhere; what this
/// file pins down is that they happen in the sequence that doesn't lose a file.
final class BoardSyncTests: XCTestCase {

    /// A shared folder in memory, which also keeps a log of what it was told to do.
    private final class FakeFolder: BoardTransport {
        var document: Data?
        var files: [String: Data] = [:]
        private(set) var log: [String] = []

        func loadDocument() async throws -> Data? { document }

        func saveDocument(_ data: Data) async throws {
            log.append("saveDocument")
            document = data
        }

        func remoteHashes() async throws -> Set<String> { Set(files.keys) }

        func download(hash: String) async throws -> Data {
            log.append("download \(hash)")
            guard let data = files[hash] else { throw CocoaError(.fileNoSuchFile) }
            return data
        }

        func upload(hash: String, data: Data) async throws {
            log.append("upload \(hash)")
            files[hash] = data
        }

        func deleteFile(hash: String) async throws {
            log.append("delete \(hash)")
            files[hash] = nil
        }
    }

    private func strip(_ id: String, _ title: String, at updated: Int64, hashes: [String] = []) -> SyncTaskRecord {
        SyncTaskRecord(
            id: id, updatedAt: updated, title: title,
            attachments: hashes.map { SyncAttachment(hash: $0, name: "\($0).jpg", kind: "image") }
        )
    }

    private func run(
        _ folder: FakeFolder,
        local: BoardSnapshot,
        localHashes: Set<String> = [],
        hasSyncedBefore: Bool = true,
        adopts: Bool = false,
        received: ((String, Data) -> Void)? = nil
    ) async throws -> BoardSyncOutcome {
        try await BoardSync(transport: folder).run(
            local: local,
            localHashes: localHashes,
            hasSyncedBefore: hasSyncedBefore,
            adoptsOnFirstSync: adopts,
            readFile: { hash in Data(hash.utf8) },
            writeFile: { hash, data in received?(hash, data) }
        )
    }

    // MARK: - The round trip

    func testAnEmptyFolderTakesThisDevicesBoard() async throws {
        let folder = FakeFolder()
        let local = BoardSnapshot(tasks: [strip("a", "Mine", at: 5)])

        let outcome = try await run(folder, local: local)

        XCTAssertTrue(outcome.pushed)
        XCTAssertFalse(outcome.pulled)
        XCTAssertEqual(outcome.summary, "Sent your changes.")
        XCTAssertNotNil(folder.document)
    }

    /// Running twice must change nothing the second time, or every sync rewrites the document and
    /// every device re-downloads it forever.
    func testASecondSyncWithNothingNewWritesNothing() async throws {
        let folder = FakeFolder()
        let local = BoardSnapshot(tasks: [strip("a", "Mine", at: 5)])
        _ = try await run(folder, local: local)

        let outcome = try await run(folder, local: BoardSnapshot(tasks: outcome0(folder).tasks))

        XCTAssertFalse(outcome.pushed)
        XCTAssertFalse(outcome.pulled)
        XCTAssertEqual(outcome.summary, "Already up to date.")
    }

    private func outcome0(_ folder: FakeFolder) -> BoardSnapshot {
        BoardSnapshot(tasks: SyncBoardDocument.tasks(from: folder.document ?? Data()))
    }

    func testTheNewerSideWinsAcrossTheRoundTrip() async throws {
        let folder = FakeFolder()
        folder.document = try SyncBoardDocument.data(tasks: [strip("a", "Theirs", at: 9)], reminders: [])

        let outcome = try await run(folder, local: BoardSnapshot(tasks: [strip("a", "Mine", at: 4)]))

        XCTAssertEqual(outcome.merged.tasks.map(\.title), ["Theirs"])
        XCTAssertTrue(outcome.pulled)
    }

    // MARK: - Ordering, which is where a file gets lost

    /// The ordering that matters most. A document naming a file the folder hasn't got is a strip
    /// arriving on the other device pointing at nothing — and it stays that way, because a sync
    /// that changes nothing writes nothing.
    func testFilesGoUpBeforeTheDocumentThatNamesThem() async throws {
        let folder = FakeFolder()
        let local = BoardSnapshot(tasks: [strip("a", "With a photo", at: 5, hashes: ["photo1"])])

        _ = try await run(folder, local: local, localHashes: ["photo1"])

        XCTAssertEqual(folder.log, ["upload photo1", "saveDocument"])
    }

    func testAFileTheFolderAlreadyHasIsNotUploadedAgain() async throws {
        let folder = FakeFolder()
        folder.files["photo1"] = Data("already there".utf8)
        let local = BoardSnapshot(tasks: [strip("a", "With a photo", at: 5, hashes: ["photo1"])])

        _ = try await run(folder, local: local, localHashes: ["photo1"])

        XCTAssertFalse(folder.log.contains("upload photo1"))
    }

    func testAFileNamedByTheMergeAndMissingHereIsFetched() async throws {
        let folder = FakeFolder()
        folder.document = try SyncBoardDocument.data(
            tasks: [strip("a", "Theirs", at: 9, hashes: ["photo2"])], reminders: []
        )
        folder.files["photo2"] = Data("their photo".utf8)
        var landed: [String: Data] = [:]

        let outcome = try await run(
            folder, local: BoardSnapshot(), received: { landed[$0] = $1 }
        )

        XCTAssertEqual(outcome.downloaded, ["photo2"])
        XCTAssertEqual(landed["photo2"], Data("their photo".utf8))
    }

    /// Deliberately not everything in the folder: a file no record mentions is one somebody is
    /// about to sweep, and pulling it down first would be work to undo.
    func testAFileNoRecordNamesIsNotFetched() async throws {
        let folder = FakeFolder()
        folder.files["stray"] = Data("nobody's".utf8)

        let outcome = try await run(folder, local: BoardSnapshot(tasks: [strip("a", "Mine", at: 5)]))

        XCTAssertTrue(outcome.downloaded.isEmpty)
    }

    /// Swept only against the merged board. Against one device's half, a file that looks
    /// unreferenced may be the only copy of something the other still has on a strip.
    func testAnOrphanIsSweptOnlyAfterTheMerge() async throws {
        let folder = FakeFolder()
        folder.files["stale"] = Data("nothing points here".utf8)
        folder.document = try SyncBoardDocument.data(tasks: [strip("a", "Theirs", at: 9)], reminders: [])

        let outcome = try await run(folder, local: BoardSnapshot())

        XCTAssertEqual(outcome.sweptAway, ["stale"])
        XCTAssertNil(folder.files["stale"])
        // And the sweep is the last thing that happens.
        XCTAssertEqual(folder.log.last, "delete stale")
    }

    func testAFileTheOtherDeviceStillNamesIsNotSwept() async throws {
        let folder = FakeFolder()
        folder.files["theirs"] = Data("still wanted".utf8)
        folder.document = try SyncBoardDocument.data(
            tasks: [strip("a", "Theirs", at: 9, hashes: ["theirs"])], reminders: []
        )

        let outcome = try await run(folder, local: BoardSnapshot())

        XCTAssertTrue(outcome.sweptAway.isEmpty)
        XCTAssertNotNil(folder.files["theirs"])
    }

    // MARK: - The first sync

    func testAdoptingTakesTheOtherBoardEntire() async throws {
        let folder = FakeFolder()
        folder.document = try SyncBoardDocument.data(tasks: [strip("theirs", "Phone's", at: 1)], reminders: [])
        let mine = BoardSnapshot(tasks: [strip("mine", "Mac's", at: 99)])

        let outcome = try await run(folder, local: mine, hasSyncedBefore: false, adopts: true)

        XCTAssertEqual(outcome.stance, .adopt)
        // Even though this device's strip is newer, it is not a merge.
        XCTAssertEqual(outcome.merged.tasks.map(\.title), ["Phone's"])
        XCTAssertEqual(outcome.summary, "Took the other device's board.")
    }

    /// The guard that matters: a first sync against an empty folder must not read "nothing" as the
    /// truth and wipe the board it was meant to protect.
    func testAdoptingAgainstAnEmptyFolderKeepsThisBoard() async throws {
        let folder = FakeFolder()
        let mine = BoardSnapshot(tasks: [strip("mine", "Mac's", at: 99)])

        let outcome = try await run(folder, local: mine, hasSyncedBefore: false, adopts: true)

        XCTAssertEqual(outcome.stance, .merge)
        XCTAssertEqual(outcome.merged.tasks.map(\.title), ["Mac's"])
    }

    // MARK: - Repairs

    /// A blocker deleted on the other device must not leave a strip blocked by a ghost.
    func testADanglingBlockerIsClearedOnTheWayIn() async throws {
        let folder = FakeFolder()
        var blocked = strip("a", "Blocked", at: 5)
        blocked.blockedBySyncID = "gone"
        folder.document = try SyncBoardDocument.data(tasks: [blocked], reminders: [])

        let outcome = try await run(folder, local: BoardSnapshot())

        XCTAssertNil(outcome.merged.tasks.first?.blockedBySyncID)
    }
}
