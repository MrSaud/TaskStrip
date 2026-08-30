import XCTest
@testable import TaskStrips

/// A drag can't be driven from a test, so what's checked is the deciding: what a dropped thing
/// turns into before any of it touches the board.
final class BoardDropTests: XCTestCase {
    // MARK: - Text

    /// The same rule promoting a quick note uses, deliberately: one answer to "turn this prose
    /// into a strip", not two that drift apart.
    func testDroppedTextBecomesAStripTitledByItsFirstLine() throws {
        let strip = try XCTUnwrap(
            BoardDrop.strip(
                fromDroppedText: "Renew the passport\nbring the old one and two photos",
                orderIndex: 4
            )
        )
        XCTAssertEqual(strip.title, "Renew the passport")
        XCTAssertEqual(strip.notes, "Renew the passport\nbring the old one and two photos")
        XCTAssertEqual(strip.orderIndex, 4)
    }

    func testALongFirstLineIsStillCappedLikeAPromotedNote() throws {
        let long = String(repeating: "a", count: 200)
        let strip = try XCTUnwrap(BoardDrop.strip(fromDroppedText: long, orderIndex: 0))
        XCTAssertEqual(strip.title.count, NotePromotion.titleLimit)
        XCTAssertEqual(strip.notes, long)
    }

    /// Dragging a selection can pick up trailing whitespace; an empty strip is worse than none.
    func testTextThatIsAllWhitespaceMakesNothing() {
        XCTAssertNil(BoardDrop.strip(fromDroppedText: "   \n\t\n ", orderIndex: 0))
        XCTAssertNil(BoardDrop.strip(fromDroppedText: "", orderIndex: 0))
    }

    func testSurroundingWhitespaceIsNotPartOfTheStrip() throws {
        let strip = try XCTUnwrap(BoardDrop.strip(fromDroppedText: "\n  Call the consulate  \n\n", orderIndex: 0))
        XCTAssertEqual(strip.title, "Call the consulate")
        XCTAssertEqual(strip.notes, "Call the consulate")
    }

    // MARK: - Files

    /// A drag from a browser carries an http URL. Attaching one would file a strip pointing at a
    /// file that never existed.
    func testOnlyRealFilesAreTaken() {
        let files = BoardDrop.usableFiles(among: [
            URL(fileURLWithPath: "/tmp/scan.pdf"),
            URL(string: "https://example.com/page")!,
            URL(fileURLWithPath: "/tmp/holiday.jpg"),
        ])
        XCTAssertEqual(files.map(\.lastPathComponent), ["scan.pdf", "holiday.jpg"])
    }

    /// The same inference a picked file gets, so a dropped photo and a chosen one land in the
    /// same place.
    func testADroppedFileLandsWhereThePickerWouldPutIt() {
        XCTAssertEqual(BoardDrop.storageType(for: URL(fileURLWithPath: "/tmp/holiday.jpg")), .image)
        XCTAssertEqual(BoardDrop.storageType(for: URL(fileURLWithPath: "/tmp/clip.mov")), .video)
        XCTAssertEqual(BoardDrop.storageType(for: URL(fileURLWithPath: "/tmp/invoice.pdf")), .document)

        XCTAssertEqual(BoardDrop.attachmentKind(for: URL(fileURLWithPath: "/tmp/holiday.jpg")), .image)
        XCTAssertEqual(BoardDrop.attachmentKind(for: URL(fileURLWithPath: "/tmp/memo.m4a")), .voiceNote)
        XCTAssertEqual(BoardDrop.attachmentKind(for: URL(fileURLWithPath: "/tmp/notes.xyz")), .document)
    }

    /// A voice note is a document as far as the library is concerned — it has three shelves, not
    /// four — but it's still a voice note on a strip.
    func testAudioIsSortedDifferentlyByTheLibraryAndByAStrip() {
        let memo = URL(fileURLWithPath: "/tmp/memo.m4a")
        XCTAssertEqual(BoardDrop.storageType(for: memo), .document)
        XCTAssertEqual(BoardDrop.attachmentKind(for: memo), .voiceNote)
    }
}
