import XCTest
@testable import TaskStrips

/// The synthesiser needs a speaker, so what's checked is what would be *said* — which is a
/// decision, not a device.
final class SpeechReaderTests: XCTestCase {
    /// Android reads a strip's notes, not its title: the title is already on screen, and reading
    /// it back adds nothing.
    func testAStripReadsItsNotes() {
        let task = TaskItem(title: "Renew the passport", orderIndex: 0)
        task.notes = "Bring the old one and two photos"
        XCTAssertEqual(SpeechReader.speech(for: task), "Bring the old one and two photos")
    }

    /// Nothing to read means the button isn't offered at all, rather than offered and silent.
    func testAStripWithNoNotesHasNothingToRead() {
        let task = TaskItem(title: "Renew the passport", orderIndex: 0)
        XCTAssertNil(SpeechReader.speech(for: task))

        task.notes = "   \n  "
        XCTAssertNil(SpeechReader.speech(for: task), "whitespace is not something to read out")
    }

    func testAReminderReadsItsTitleThenItsDetails() {
        let reminder = Reminder(
            text: "Renew the registration",
            triggerAt: .now,
            details: "Istimara expires this month"
        )
        XCTAssertEqual(
            SpeechReader.speech(for: reminder),
            "Renew the registration. Istimara expires this month"
        )
    }

    /// The full stop is what makes the synthesiser pause between the two; with no details there's
    /// nothing to pause before.
    func testAReminderWithNoDetailsReadsJustItsTitle() {
        let reminder = Reminder(text: "Dentist", triggerAt: .now)
        XCTAssertEqual(SpeechReader.speech(for: reminder), "Dentist")
    }
}
