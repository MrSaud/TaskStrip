import XCTest
@testable import TaskStrips

/// The parser is the whole of the voice feature that can be checked without a microphone, and
/// it's also the part that decides what gets filed — so every rule ported from
/// VoiceCommandParser.kt has a case here.
final class VoiceCommandParserTests: XCTestCase {
    // MARK: - The opening phrase

    func testTheLeadingPhraseIsDropped() {
        XCTAssertEqual(VoiceCommandParser.parse("add a strip for renew the passport").title, "Renew the passport")
        XCTAssertEqual(VoiceCommandParser.parse("create a task book flights").title, "Book flights")
        XCTAssertEqual(VoiceCommandParser.parse("file a strip pay the invoice").title, "Pay the invoice")
    }

    /// Longest first, or "create a strip for X" would keep the stray "for".
    func testTheLongestMatchingPhraseWins() {
        XCTAssertEqual(VoiceCommandParser.parse("create a strip for the visa").title, "The visa")
    }

    func testAPhraseInTheMiddleIsNotAnOpening() {
        XCTAssertEqual(
            VoiceCommandParser.parse("remind the office to add a strip").title,
            "Remind the office to add a strip"
        )
    }

    func testSomethingSaidWithNoPreambleIsStillAStrip() {
        XCTAssertEqual(VoiceCommandParser.parse("renew the passport").title, "Renew the passport")
    }

    // MARK: - Splitting title from notes

    func testADescriptionKeywordSplitsTheSentence() {
        let draft = VoiceCommandParser.parse(
            "create a strip for project a, description is call the vendor about pricing"
        )
        XCTAssertEqual(draft.title, "Project a")
        XCTAssertEqual(draft.notes, "call the vendor about pricing")
    }

    func testEveryDescriptionKeywordIsRecognised() {
        for keyword in ["the description is", "description is", "notes are", "notes is",
                        "with description", "description", "notes"] {
            let draft = VoiceCommandParser.parse("add a strip renew the visa \(keyword) bring photos")
            XCTAssertEqual(draft.notes, "bring photos", "\"\(keyword)\" should introduce the notes")
            XCTAssertEqual(draft.title, "Renew the visa", "\"\(keyword)\" should end the title")
        }
    }

    /// With no keyword, the first comma is the seam.
    func testACommaSplitsWhenThereIsNoKeyword() {
        let draft = VoiceCommandParser.parse("renew the passport, before the trip in May")
        XCTAssertEqual(draft.title, "Renew the passport")
        XCTAssertEqual(draft.notes, "before the trip in May")
    }

    func testWithNeitherTheWholeThingIsTheTitle() {
        let draft = VoiceCommandParser.parse("renew the passport this week")
        XCTAssertEqual(draft.title, "Renew the passport this week")
        XCTAssertTrue(draft.notes.isEmpty)
    }

    /// A keyword after a comma still wins, because it's the more deliberate of the two signals.
    func testTheEarliestKeywordWinsOverALaterOne() {
        let draft = VoiceCommandParser.parse("book flights notes call the agent description is later")
        XCTAssertEqual(draft.title, "Book flights")
        XCTAssertEqual(draft.notes, "call the agent description is later")
    }

    // MARK: - Priority

    func testEachSpokenPriorityIsUnderstood() {
        XCTAssertEqual(VoiceCommandParser.parse("add a strip renew the visa, urgent").priority, .urgent)
        XCTAssertEqual(VoiceCommandParser.parse("add a strip renew the visa high priority").priority, .high)
        XCTAssertEqual(VoiceCommandParser.parse("add a strip renew the visa low priority").priority, .low)
        XCTAssertEqual(VoiceCommandParser.parse("add a strip renew the visa normal priority").priority, .normal)
    }

    func testNoPrioritySpokenLeavesItUnset() {
        XCTAssertNil(VoiceCommandParser.parse("add a strip renew the visa").priority)
    }

    /// The word comes out of the title — a strip called "Renew the visa urgent" reads badly on
    /// the board.
    func testThePriorityWordIsTakenOutOfTheTitle() {
        let draft = VoiceCommandParser.parse("add a strip for renew the visa urgent")
        XCTAssertEqual(draft.title, "Renew the visa")
        XCTAssertEqual(draft.priority, .urgent)
    }

    /// Android's own cleanup misses this: lifting the word out leaves ", ," and its literal
    /// ",," replacement never matches, so its title keeps a comma. This one doesn't.
    func testTheDanglingCommaGoesWithIt() {
        let draft = VoiceCommandParser.parse("add a strip renew the visa, urgent, notes bring photos")
        XCTAssertEqual(draft.title, "Renew the visa")
        XCTAssertEqual(draft.notes, "bring photos")
        XCTAssertEqual(draft.priority, .urgent)
    }

    /// Word boundaries, so a title that merely contains the letters isn't reclassified.
    func testAWordThatMerelyContainsAPriorityIsNotOne() {
        let draft = VoiceCommandParser.parse("add a strip chase the urgently needed part")
        XCTAssertNil(draft.priority)
        XCTAssertEqual(draft.title, "Chase the urgently needed part")
    }

    func testMatchingIgnoresCase() {
        let draft = VoiceCommandParser.parse("ADD A STRIP FOR Renew The Visa, URGENT")
        XCTAssertEqual(draft.priority, .urgent)
        XCTAssertEqual(draft.title, "Renew The Visa")
    }

    // MARK: - Not losing what was said

    /// If the matching strips everything away, what the user actually said is filed rather than
    /// an empty strip.
    func testASentenceThatIsNothingButAPreambleKeepsItself() {
        XCTAssertEqual(VoiceCommandParser.parse("add a strip").title, "Add a strip")
    }

    func testTheTitleIsCapitalised() {
        XCTAssertEqual(VoiceCommandParser.parse("add a strip renew the passport").title, "Renew the passport")
    }

    func testSurroundingSpaceIsIgnored() {
        XCTAssertEqual(VoiceCommandParser.parse("   add a strip renew the visa   ").title, "Renew the visa")
    }

    func testAnEmptySentenceProducesAnEmptyDraftRatherThanCrashing() {
        let draft = VoiceCommandParser.parse("")
        XCTAssertTrue(draft.title.isEmpty)
        XCTAssertTrue(draft.notes.isEmpty)
        XCTAssertNil(draft.priority)
    }
}
