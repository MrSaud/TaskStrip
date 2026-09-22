import XCTest
@testable import TaskStrips

/// The hand-off from the iPhone's Share Extension to the app. Against a temporary folder standing
/// in for the App Group.
final class ShareInboxTests: XCTestCase {
    private var root: URL!
    private var source: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShareInboxTests-\(UUID().uuidString)")
        source = FileManager.default.temporaryDirectory.appending(path: "ShareInboxSource-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: source)
    }

    private func file(_ name: String, _ text: String = "bytes") throws -> URL {
        let url = source.appending(path: UUID().uuidString).appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testAnEntryComesBackWithItsFiles() throws {
        let entry = SharedEntry(kind: .files, tag: "Receipts")
        try ShareInbox.add(entry, files: [try file("scan.pdf", "pdf")], root: root)

        let pending = ShareInbox.pending(root: root)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].entry.tag, "Receipts")
        XCTAssertEqual(pending[0].entry.fileNames, ["scan.pdf"])
        XCTAssertEqual(try String(contentsOf: pending[0].folder.appending(path: "scan.pdf")), "pdf")
    }

    /// Two photos called IMG_0001.jpg must not overwrite each other.
    func testFilesWithTheSameNameAreBothKept() throws {
        try ShareInbox.add(SharedEntry(kind: .files), files: [try file("IMG_0001.jpg", "a"), try file("IMG_0001.jpg", "b")], root: root)

        let entry = try XCTUnwrap(ShareInbox.pending(root: root).first?.entry)
        XCTAssertEqual(entry.fileNames, ["IMG_0001.jpg", "IMG_0001 2.jpg"])
    }

    /// The entry's JSON is written last, so a folder without one is an entry still being written.
    func testAFolderWithoutItsEntryIsNotPickedUp() throws {
        try FileManager.default.createDirectory(at: root.appending(path: UUID().uuidString), withIntermediateDirectories: true)
        XCTAssertTrue(ShareInbox.pending(root: root).isEmpty)
    }

    func testEntriesComeBackOldestFirstAndGoWhenRemoved() throws {
        try ShareInbox.add(SharedEntry(kind: .strip, title: "Second", createdAt: .now), files: [], root: root)
        try ShareInbox.add(SharedEntry(kind: .strip, title: "First", createdAt: .now.addingTimeInterval(-60)), files: [], root: root)

        let pending = ShareInbox.pending(root: root)
        XCTAssertEqual(pending.map(\.entry.title), ["First", "Second"])

        ShareInbox.remove(pending[0].folder)
        XCTAssertEqual(ShareInbox.pending(root: root).map(\.entry.title), ["Second"])
    }
}
