import SwiftData
import XCTest
@testable import TaskStrips

/// A date read off a document, turned into a reminder somebody will actually get.
@MainActor
final class DocumentReminderTests: XCTestCase {
    private var context: ModelContext!
    private let calendar = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        try super.setUpWithError()
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func found(_ kind: DocumentDates.Meaning, on day: Int = 15, month: Int = 3, year: Int = 2027, hour: Int = 0) -> FoundDate {
        var parts = DateComponents()
        parts.day = day
        parts.month = month
        parts.year = year
        parts.hour = hour
        return FoundDate(
            date: calendar.date(from: parts) ?? .distantFuture,
            matched: "15 March 2027",
            context: "Payment due by 15 March 2027",
            kind: kind
        )
    }

    /// Midnight is a reminder that arrives while somebody is asleep and is gone by breakfast.
    func testADateWithNoTimeInItSpeaksInTheMorning() {
        let when = DocumentReminder.triggerAt(found(.deadline).date, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: when), DocumentReminder.hour)
        XCTAssertEqual(calendar.component(.day, from: when), 15)
    }

    /// "3pm on the 14th" means 3pm.
    func testADateThatCarriesATimeKeepsIt() {
        let afternoon = found(.appointment, hour: 15)
        XCTAssertEqual(DocumentReminder.triggerAt(afternoon.date, calendar: calendar), afternoon.date)
    }

    /// A passport that expires today is already a problem; a week's notice is what makes it
    /// something somebody can act on.
    func testADeadlineAndAnExpiryWarnAWeekAhead() {
        XCTAssertEqual(DocumentReminder.leadMinutes(for: .deadline), 7 * 24 * 60)
        XCTAssertEqual(DocumentReminder.leadMinutes(for: .expiry), 7 * 24 * 60)
    }

    /// An appointment is about the day itself.
    func testAnAppointmentComesOnTheDay() {
        XCTAssertNil(DocumentReminder.leadMinutes(for: .appointment))
        XCTAssertNil(DocumentReminder.leadMinutes(for: .unknown))
    }

    func testItIsCalledWhatTheDocumentCalledIt() {
        XCTAssertEqual(
            DocumentReminder.title(for: found(.expiry), document: "passport.pdf", strip: "Renew passport"),
            "Expires — Renew passport"
        )
        // With no strip behind it, the file's own name will do.
        XCTAssertEqual(
            DocumentReminder.title(for: found(.expiry), document: "passport.pdf"),
            "Expires — passport.pdf"
        )
        XCTAssertEqual(
            DocumentReminder.title(for: found(.unknown), document: "letter.pdf"),
            "Date — letter.pdf"
        )
    }

    /// The line it was read from, so the reminder can be checked without opening the document.
    func testTheDetailsSayWhereItCameFrom() {
        let details = DocumentReminder.details(for: found(.deadline), document: "invoice.pdf")
        XCTAssertTrue(details.contains("Payment due by 15 March 2027"), details)
        XCTAssertTrue(details.contains("Read from invoice.pdf"), details)
    }

    /// The whole point of the change: a row in the reminders list, not a flag on a strip.
    func testAReminderIsARowOfItsOwn() throws {
        let reminder = Reminder(
            text: DocumentReminder.title(for: found(.expiry), document: "passport.pdf", strip: "Renew passport"),
            triggerAt: DocumentReminder.triggerAt(found(.expiry).date, calendar: calendar),
            details: DocumentReminder.details(for: found(.expiry), document: "passport.pdf"),
            leadMinutesBefore: DocumentReminder.leadMinutes(for: .expiry),
            tag: "HOME"
        )
        context.insert(reminder)

        let stored = try context.fetch(FetchDescriptor<Reminder>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.text, "Expires — Renew passport")
        XCTAssertEqual(stored.first?.leadMinutesBefore, 7 * 24 * 60)
        XCTAssertEqual(stored.first?.tag, "HOME")
    }
}
