import XCTest
@testable import TaskStrips

/// Works in a temporary directory rather than the real media root — the store takes its root as
/// an argument precisely so this can't touch anything real.
final class AttachmentStoreTests: XCTestCase {
    private var root: URL!
    private var scratch: URL!
    private var store: AttachmentStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "attachment-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        scratch = FileManager.default.temporaryDirectory
            .appending(path: "attachment-source-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        store = AttachmentStore(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: scratch)
    }

    private func makeFile(named name: String, contents: String = "hello") throws -> URL {
        let url = scratch.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: - Kind inference

    func testInfersKindFromTheExtension() {
        XCTAssertEqual(AttachmentKind.inferred(fromExtension: "JPG"), .image)
        XCTAssertEqual(AttachmentKind.inferred(fromExtension: "heic"), .image)
        XCTAssertEqual(AttachmentKind.inferred(fromExtension: "mov"), .video)
        XCTAssertEqual(AttachmentKind.inferred(fromExtension: "m4a"), .voiceNote)
        XCTAssertEqual(AttachmentKind.inferred(fromExtension: "pdf"), .document)
        XCTAssertEqual(AttachmentKind.inferred(fromExtension: ""), .document)
        XCTAssertEqual(AttachmentKind.inferred(fromExtension: "wobble"), .document)
    }

    /// The folder names have to match Android's filesDir layout or imported paths land in the
    /// wrong place. Voice notes are the one that doesn't match its own name.
    func testFoldersMirrorTheAndroidLayout() {
        XCTAssertEqual(AttachmentKind.image.folder, "images")
        XCTAssertEqual(AttachmentKind.voiceNote.folder, "audio")
        XCTAssertEqual(AttachmentKind.document.folder, "documents")
        XCTAssertEqual(AttachmentKind.video.folder, "videos")
    }

    func testBackupKeysMatchTheTaskJSON() {
        XCTAssertEqual(AttachmentKind.image.backupKey, "images")
        XCTAssertEqual(AttachmentKind.voiceNote.backupKey, "voiceNotes")
        XCTAssertEqual(AttachmentKind.document.backupKey, "documents")
        XCTAssertEqual(AttachmentKind.video.backupKey, "videos")
    }

    // MARK: - Adding

    func testAddCopiesTheFileAndLeavesTheOriginal() throws {
        let source = try makeFile(named: "receipt.pdf", contents: "pdf bytes")
        let attachment = try store.add(contentsOf: source)

        XCTAssertTrue(store.exists(attachment))
        XCTAssertEqual(try String(contentsOf: store.url(for: attachment), encoding: .utf8), "pdf bytes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the original must survive")
    }

    func testStoredPathsAreRelativeToTheRoot() throws {
        let attachment = try store.add(contentsOf: try makeFile(named: "shot.png"))
        XCTAssertFalse(attachment.path.hasPrefix("/"), "paths must be relative: \(attachment.path)")
        XCTAssertTrue(attachment.path.hasPrefix("images/"), attachment.path)
        XCTAssertEqual(store.url(for: attachment).path, root.appending(path: attachment.path).path)
    }

    func testANonDocumentIsRenamedButKeepsItsExtension() throws {
        let attachment = try store.add(contentsOf: try makeFile(named: "IMG_0042.jpg"))
        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual((attachment.path as NSString).pathExtension, "jpg")
        XCTAssertFalse(attachment.path.contains("IMG_0042"), "the stored name is a uuid")
        XCTAssertEqual(attachment.name, "IMG_0042.jpg", "but the display name is the original")
    }

    /// Documents keep their name because it's the only thing identifying them in the UI, so they
    /// each get a folder to avoid collisions — the same trick MediaStorage uses.
    func testTwoDocumentsWithTheSameNameDoNotCollide() throws {
        let first = try store.add(contentsOf: try makeFile(named: "invoice.pdf", contents: "one"))
        try FileManager.default.removeItem(at: scratch.appending(path: "invoice.pdf"))
        let second = try store.add(contentsOf: try makeFile(named: "invoice.pdf", contents: "two"))

        XCTAssertNotEqual(first.path, second.path)
        XCTAssertTrue(first.path.hasSuffix("/invoice.pdf"))
        XCTAssertTrue(second.path.hasSuffix("/invoice.pdf"))
        XCTAssertEqual(try String(contentsOf: store.url(for: first), encoding: .utf8), "one")
        XCTAssertEqual(try String(contentsOf: store.url(for: second), encoding: .utf8), "two")
    }

    func testAddingReportsAMissingSource() {
        let missing = scratch.appending(path: "not-there.png")
        XCTAssertThrowsError(try store.add(contentsOf: missing))
    }

    // MARK: - Writing bytes, the import path

    func testWriteCreatesIntermediateFolders() throws {
        try store.write(Data("jpeg".utf8), toRelativePath: "images/nested/deep/photo.jpg")
        let written = root.appending(path: "images/nested/deep/photo.jpg")
        XCTAssertEqual(try String(contentsOf: written, encoding: .utf8), "jpeg")
    }

    // MARK: - Removing

    func testRemoveDeletesTheFile() throws {
        let attachment = try store.add(contentsOf: try makeFile(named: "clip.mov"))
        XCTAssertTrue(store.exists(attachment))

        store.remove(attachment)
        XCTAssertFalse(store.exists(attachment))
    }

    /// A removed document shouldn't leave its uuid folder behind.
    func testRemovingADocumentTakesItsFolderWithIt() throws {
        let attachment = try store.add(contentsOf: try makeFile(named: "notes.txt"))
        let folder = store.url(for: attachment).deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))

        store.remove(attachment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appending(path: "documents").path),
            "but not the documents folder itself"
        )
    }
}
