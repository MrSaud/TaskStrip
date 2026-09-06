import XCTest
@testable import TaskStrips

/// Mirrors SyncFileStoreTest.kt case for case — the two devices name files in the same shared
/// folder and have to agree, byte for byte, on what they are called.
final class SyncFileStoreTests: XCTestCase {

    private var folder = URL(fileURLWithPath: NSTemporaryDirectory())

    /// The published SHA-256 of "abc". If this ever disagrees with the Kotlin suite's copy, the
    /// two devices are naming the same bytes differently and every file syncs twice.
    private let hashOfABC = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "SyncFileStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, _ contents: String) throws -> URL {
        let url = folder.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testAFileIsNamedByWhatIsInsideIt() throws {
        let url = try file("anything.txt", "abc")

        XCTAssertEqual(try SyncFileStore.hash(contentsOf: url), hashOfABC)
    }

    func testTheNameDoesNotDependOnTheFilesOwnName() throws {
        let one = try file("photo.jpg", "same bytes")
        let two = try file("copy-of-photo.jpg", "same bytes")

        XCTAssertEqual(try SyncFileStore.hash(contentsOf: one), try SyncFileStore.hash(contentsOf: two))
    }

    /// Hashing streams rather than reading whole, because a video attachment would otherwise have
    /// to fit in memory. This is bigger than the read buffer, so it exercises more than one block.
    func testAFileLargerThanTheReadBufferHashesTheSameAsItsBytes() throws {
        let bytes = Data((0..<(200 * 1024)).map { UInt8($0 % 251) })
        let url = folder.appending(path: "big.bin")
        try bytes.write(to: url)

        XCTAssertEqual(try SyncFileStore.hash(contentsOf: url), SyncFileStore.hash(bytes))
    }

    func testRemoteNamesRoundTrip() {
        XCTAssertEqual(SyncFileStore.remoteName(hashOfABC), "file-\(hashOfABC)")
        XCTAssertEqual(SyncFileStore.hash(fromRemoteName: "file-\(hashOfABC)"), hashOfABC)
        XCTAssertTrue(SyncFileStore.isStoreName("file-\(hashOfABC)"))
        XCTAssertFalse(SyncFileStore.isStoreName("sync_board.json"))
        XCTAssertNil(SyncFileStore.hash(fromRemoteName: "sync_board.json"))
        // The prefix alone names nothing.
        XCTAssertNil(SyncFileStore.hash(fromRemoteName: "file-"))
    }

    func testOnlyFilesThisDeviceHoldsAndTheFolderLacksAreUploaded() {
        let upload = SyncFileStore.toUpload(
            referenced: ["a", "b", "c"],
            remote: ["a"],
            localHashes: ["a", "b", "d"]
        )

        // "c" is referenced but this device hasn't got it — that's a download, not an upload.
        // "d" is here but nothing points at it.
        XCTAssertEqual(upload, ["b"])
    }

    func testOnlyFilesTheBoardPointsAtAreDownloaded() {
        XCTAssertEqual(SyncFileStore.toDownload(referenced: ["a", "b"], localHashes: ["a"]), ["b"])
    }

    func testAnOrphanIsAFileNothingPointsAtAnyMore() {
        XCTAssertEqual(SyncFileStore.orphans(remote: ["live", "stale"], referenced: ["live"]), ["stale"])
    }

    /// Two devices adding the same photo must not produce two files.
    func testTheSameContentAddedTwiceIsOneFile() throws {
        let mine = try file("mine.png", "identical")
        let theirs = try file("theirs.png", "identical")

        let remote: Set<String> = [try SyncFileStore.hash(contentsOf: mine)]
        let upload = SyncFileStore.toUpload(
            referenced: [try SyncFileStore.hash(contentsOf: theirs)],
            remote: remote,
            localHashes: [try SyncFileStore.hash(contentsOf: theirs)]
        )

        XCTAssertTrue(upload.isEmpty)
    }
}
