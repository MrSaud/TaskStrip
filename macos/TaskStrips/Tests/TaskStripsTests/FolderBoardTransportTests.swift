import XCTest
@testable import TaskStrips

/// The folder transport against a real folder, because that is the only way to find out whether it
/// actually reads and writes what it claims.
final class FolderBoardTransportTests: XCTestCase {

    private var folder = URL(fileURLWithPath: NSTemporaryDirectory())
    private var transport = FolderBoardTransport(folder: URL(fileURLWithPath: "/"))

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "FolderBoardTransportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        transport = FolderBoardTransport(folder: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - The document

    /// An empty folder is nothing to add, never an error and never a reason to empty this machine.
    func testAFolderWithNoDocumentReadsAsNothing() async throws {
        let loaded = try await transport.loadDocument()

        XCTAssertNil(loaded)
    }

    func testADocumentSurvivesTheRoundTrip() async throws {
        let strip = SyncTaskRecord(id: "a", updatedAt: 5, title: "Renew the insurance")
        let written = try SyncBoardDocument.data(tasks: [strip], reminders: [])

        try await transport.saveDocument(written)
        let read = try await transport.loadDocument()

        XCTAssertEqual(SyncBoardDocument.tasks(from: try XCTUnwrap(read)).map(\.title), ["Renew the insurance"])
    }

    /// Saving twice must leave one document, not a document and the staging file it was written
    /// through — a stray file in a folder Drive is watching is a stray file on both machines.
    func testSavingLeavesNothingBehindButTheDocument() async throws {
        try await transport.saveDocument(try SyncBoardDocument.data(tasks: [], reminders: []))
        try await transport.saveDocument(try SyncBoardDocument.data(tasks: [], reminders: []))

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)

        XCTAssertEqual(names, [SyncBoardDocument.fileName])
    }

    // MARK: - Files

    func testAFileSurvivesTheRoundTripAndIsListed() async throws {
        let bytes = Data("a photo".utf8)
        let hash = SyncFileStore.hash(bytes)

        try await transport.upload(hash: hash, data: bytes)

        let listed = try await transport.remoteHashes()
        let fetched = try await transport.download(hash: hash)
        XCTAssertEqual(listed, [hash])
        XCTAssertEqual(fetched, bytes)
    }

    /// The document sits in the same folder as the files and must never be mistaken for one.
    func testTheDocumentIsNotCountedAsAFile() async throws {
        try await transport.saveDocument(try SyncBoardDocument.data(tasks: [], reminders: []))

        let listed = try await transport.remoteHashes()
        XCTAssertTrue(listed.isEmpty)
    }

    /// A file's name is the hash of its contents, so a second upload under the same name is the
    /// same bytes — which is what two devices adding the same photo looks like.
    func testUploadingTheSameFileTwiceIsHarmless() async throws {
        let bytes = Data("identical".utf8)
        let hash = SyncFileStore.hash(bytes)

        try await transport.upload(hash: hash, data: bytes)
        try await transport.upload(hash: hash, data: bytes)

        let listed = try await transport.remoteHashes()
        let fetched = try await transport.download(hash: hash)
        XCTAssertEqual(listed, [hash])
        XCTAssertEqual(fetched, bytes)
        // And no staging file left over from the second attempt.
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        XCTAssertEqual(names, [SyncFileStore.remoteName(hash)])
    }

    func testDeletingAnOrphanRemovesIt() async throws {
        let bytes = Data("stale".utf8)
        let hash = SyncFileStore.hash(bytes)
        try await transport.upload(hash: hash, data: bytes)

        try await transport.deleteFile(hash: hash)

        let listed = try await transport.remoteHashes()
        XCTAssertTrue(listed.isEmpty)
    }

    /// Deleting something already gone is not a failure — two devices can sweep the same orphan.
    func testDeletingAFileThatIsAlreadyGoneIsFine() async throws {
        try await transport.deleteFile(hash: "neverexisted")
    }
}
