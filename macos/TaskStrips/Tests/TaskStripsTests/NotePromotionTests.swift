import XCTest
@testable import TaskStrips

/// The rules NotesScreen.kt applies when a jotted thought becomes work.
final class NotePromotionTests: XCTestCase {
    func testPromotionTakesTheFirstLineAsTheTitleAndKeepsTheWholeText() {
        let note = Note(text: "Call the consulate\nask about the appointment slot")
        let strip = NotePromotion.strip(from: note, orderIndex: 7)

        XCTAssertEqual(strip.title, "Call the consulate")
        XCTAssertEqual(strip.notes, note.text)
        XCTAssertEqual(strip.orderIndex, 7)
        XCTAssertEqual(strip.priority, .normal)
        XCTAssertNil(strip.dueAt)
    }

    func testPromotionTruncatesALongTitleButNotTheNotes() {
        let long = String(repeating: "a", count: 200)
        let strip = NotePromotion.strip(from: Note(text: long), orderIndex: 0)

        XCTAssertEqual(strip.title.count, NotePromotion.titleLimit)
        XCTAssertEqual(strip.notes, long)
    }

    /// Android takes `lineSequence().firstOrNull()`, which on a note that opens with a blank line
    /// yields an empty title. Skipping to the first line with something in it is the same intent
    /// without the strip that reads as untitled on the board.
    func testPromotionSkipsLeadingBlankLines() {
        let strip = NotePromotion.strip(from: Note(text: "\n   \nGet the visa photos"), orderIndex: 0)
        XCTAssertEqual(strip.title, "Get the visa photos")
    }

    func testSplitLinesDropsBlanksAndTrims() {
        let lines = NotePromotion.splitLines(of: "  first  \n\n   \nsecond\n")
        XCTAssertEqual(lines, ["first", "second"])
    }

    /// The gate on offering the split at all: one line means splitting would only throw the
    /// note's text away.
    func testASingleLineNoteHasNothingToSplit() {
        XCTAssertEqual(NotePromotion.splitLines(of: "  one thing  ").count, 1)
    }

    func testSplittingFilesOneStripPerLineInOrder() {
        let note = Note(text: "book flights\n\nrenew passport\npack")
        let strips = NotePromotion.strips(splitting: note, startingAt: 3)

        XCTAssertEqual(strips.map(\.title), ["book flights", "renew passport", "pack"])
        XCTAssertEqual(strips.map(\.orderIndex), [3, 4, 5])
        // The lines are the titles; nothing is duplicated into the notes field.
        XCTAssertTrue(strips.allSatisfy { $0.notes.isEmpty })
    }

    func testSplittingStripsCheckboxPrefixes() {
        let note = Note(text: "[ ] socks\n[x] adapter\n[X] charger\n[✓] passport\nvisa")
        let strips = NotePromotion.strips(splitting: note, startingAt: 0)

        XCTAssertEqual(strips.map(\.title), ["socks", "adapter", "charger", "passport", "visa"])
    }

    /// A line that is *only* a checkbox would otherwise become a strip with no title at all, so
    /// the original line stands — Android's `cleaned.ifBlank { line }`.
    func testALineThatIsNothingButACheckboxKeepsItsText() {
        let strips = NotePromotion.strips(splitting: Note(text: "[ ]\nreal item"), startingAt: 0)
        XCTAssertEqual(strips.map(\.title), ["[ ]", "real item"])
    }

    func testSplittingTruncatesEachTitle() {
        let long = String(repeating: "b", count: 120)
        let strips = NotePromotion.strips(splitting: Note(text: "short\n\(long)"), startingAt: 0)

        XCTAssertEqual(strips.map(\.title.count), [5, NotePromotion.titleLimit])
    }

    /// A checkbox marker anywhere but the front is part of the text, not formatting.
    func testACheckboxMidLineIsLeftAlone() {
        XCTAssertEqual(NotePromotion.stripCheckbox(from: "ask if [x] applies"), "ask if [x] applies")
    }
}
