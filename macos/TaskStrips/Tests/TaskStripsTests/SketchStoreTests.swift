import XCTest
@testable import TaskStrips

/// The layout SketchStorage.kt writes, read back here — a note that came off a phone has to open
/// on the Mac, and one drawn here has to open on the phone.
final class SketchStoreTests: XCTestCase {

    private var root: URL!
    private var store: SketchStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "SketchStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = SketchStore(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writePage(_ name: String, in note: String, bytes: Data = Data([0x89, 0x50])) throws {
        let folder = root.appending(path: note, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try bytes.write(to: folder.appending(path: name))
    }

    func testPagesComeBackInPageOrderNotAlphabeticalOrder() throws {
        for page in ["page1.png", "page2.png", "page10.png", "page11.png"] {
            try writePage(page, in: "note_1")
        }

        XCTAssertEqual(
            store.pages(of: "note_1").map(\.lastPathComponent),
            ["page1.png", "page2.png", "page10.png", "page11.png"]
        )
    }

    func testTheNextPageFollowsTheHighestNumberNotTheCount() throws {
        try writePage("page1.png", in: "note_1")
        try writePage("page7.png", in: "note_1")

        XCTAssertEqual(store.nextPageURL(of: "note_1").lastPathComponent, "page8.png")
    }

    func testTheFirstPageOfANewNoteIsPageOne() {
        XCTAssertEqual(store.nextPageURL(of: "note_new").lastPathComponent, "page1.png")
    }

    func testAFolderWithNoPagesIsNotANote() throws {
        try FileManager.default.createDirectory(
            at: root.appending(path: "note_empty"), withIntermediateDirectories: true
        )

        XCTAssertNil(store.note("note_empty"))
        XCTAssertTrue(store.notes().isEmpty)
    }

    func testANewNoteIDDoesNotTouchTheDisk() {
        let id = SketchStore.newNoteID()

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(of: id).path))
        XCTAssertTrue(store.notes().isEmpty)
    }

    func testTheNoteIDCarriesTheMomentItWasStarted() {
        let started = Date(timeIntervalSince1970: 1_787_000_000)

        XCTAssertEqual(SketchStore.newNoteID(now: started), "note_1787000000000")
    }

    func testNotesAreNewestFirst() throws {
        try writePage("page1.png", in: "older")
        try writePage("page1.png", in: "newer")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
            ofItemAtPath: root.appending(path: "older/page1.png").path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000_000)],
            ofItemAtPath: root.appending(path: "newer/page1.png").path
        )

        XCTAssertEqual(store.notes().map(\.id), ["newer", "older"])
    }

    /// The folder's own date doesn't move when a page is redrawn in place, so the note's does.
    func testANoteIsAsRecentAsItsMostRecentlyEditedPage() throws {
        try writePage("page1.png", in: "note_1")
        try writePage("page2.png", in: "note_1")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
            ofItemAtPath: root.appending(path: "note_1/page1.png").path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 9_000_000)],
            ofItemAtPath: root.appending(path: "note_1/page2.png").path
        )

        XCTAssertEqual(store.lastModified(of: "note_1"), Date(timeIntervalSince1970: 9_000_000))
    }

    // MARK: - Names

    func testANameIsAHiddenFileThatIsNeverMistakenForAPage() throws {
        try writePage("page1.png", in: "note_1")
        store.setName("Kitchen plan", of: "note_1")

        XCTAssertEqual(store.name(of: "note_1"), "Kitchen plan")
        XCTAssertEqual(store.pages(of: "note_1").count, 1)
        XCTAssertEqual(store.note("note_1")?.displayName, "Kitchen plan")
    }

    func testAnEmptyNameRemovesTheNameRatherThanStoringNothing() throws {
        try writePage("page1.png", in: "note_1")
        store.setName("Kitchen plan", of: "note_1")

        store.setName("   ", of: "note_1")

        XCTAssertNil(store.name(of: "note_1"))
    }

    func testAnUnnamedNoteFallsBackToWhenItWasLastTouched() throws {
        try writePage("page1.png", in: "note_1")
        let touched = Date(timeIntervalSince1970: 1_787_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: touched], ofItemAtPath: root.appending(path: "note_1/page1.png").path
        )

        XCTAssertEqual(store.note("note_1")?.displayName, SketchStore.dateLabel(touched))
    }

    // MARK: - Created

    func testTheCreatedStampIsWrittenOnceAndNotMoved() throws {
        try writePage("page1.png", in: "note_1")
        let first = Date(timeIntervalSince1970: 1_700_000_000)

        store.stampCreatedIfMissing("note_1", now: first)
        store.stampCreatedIfMissing("note_1", now: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertEqual(store.createdAt(of: "note_1"), first)
    }

    /// Sketches drawn before the stamp existed — which is every sketch on the phone older than
    /// that change — still know when they were started, from their own folder name.
    func testANoteWithNoStampFallsBackToTheTimeInItsName() throws {
        try writePage("page1.png", in: "note_1787000000000")

        XCTAssertEqual(
            store.createdAt(of: "note_1787000000000"),
            Date(timeIntervalSince1970: 1_787_000_000)
        )
    }

    func testANoteNamedSomethingElseEntirelyFallsBackToItsPages() throws {
        try writePage("page1.png", in: "imported-by-hand")
        let touched = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: touched],
            ofItemAtPath: root.appending(path: "imported-by-hand/page1.png").path
        )

        XCTAssertEqual(store.createdAt(of: "imported-by-hand"), touched)
    }

    // MARK: - Removing

    func testDeletingAPageLeavesTheRestOfTheNote() throws {
        try writePage("page1.png", in: "note_1")
        try writePage("page2.png", in: "note_1")

        store.deletePage(store.pages(of: "note_1")[0])

        XCTAssertEqual(store.pages(of: "note_1").map(\.lastPathComponent), ["page2.png"])
    }

    /// Deleting takes the drawing and its name, and leaves a tombstone.
    ///
    /// The folder survives on purpose: removed outright, the note would be indistinguishable from
    /// one the other device has never seen, and the next sync would draw it again. What is left is
    /// only a name to be deleted by and the moment it happened — never anything that still reads
    /// like content.
    func testDeletingANoteTakesItsPagesAndItsNameButLeavesATombstone() throws {
        try writePage("page1.png", in: "note_1")
        store.setName("Kitchen plan", of: "note_1")
        let id = store.syncID(of: "note_1")

        store.deleteNote("note_1")

        XCTAssertTrue(store.pages(of: "note_1").isEmpty)
        XCTAssertNil(store.name(of: "note_1"))
        XCTAssertTrue(store.notes().isEmpty)
        // But the sync can still say what went and when.
        XCTAssertTrue(store.isDeleted("note_1"))
        XCTAssertEqual(store.syncID(of: "note_1"), id)
        XCTAssertGreaterThan(store.deletedAt(of: "note_1"), 0)
    }
}
