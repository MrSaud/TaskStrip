import XCTest
@testable import TaskStrips

/// Making a strip out of a message, which is the step that was still being done by hand.
final class StripFromMailTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)   // 21 Sep 2026

    private func message(
        subject: String = "Tender 4471 — documents required",
        sender: String = "Mona Salmeen <msalmeen@kfas.org.kw>"
    ) -> MailMessage {
        MailMessage(
            id: "abc@kfas.org.kw", subject: subject, sender: sender,
            receivedAt: now.addingTimeInterval(-3_600), isRead: false
        )
    }

    func testTheSubjectBecomesTheTitleAndTheSenderBecomesAContact() {
        let plan = StripFromMail.plan(for: message(), body: MailBody(text: "Please send the papers."), now: now)
        XCTAssertEqual(plan.title, "Tender 4471 — documents required")
        XCTAssertEqual(plan.contactName, "Mona Salmeen")
        XCTAssertEqual(plan.contactEmail, "msalmeen@kfas.org.kw")
    }

    func testTheLinkBackToTheMessageComesTooSoTheStripCanBeTracedToIt() {
        let plan = StripFromMail.plan(for: message(), body: nil, now: now)
        XCTAssertEqual(plan.link, "message://%3Cabc@kfas.org.kw%3E")
        XCTAssertEqual(plan.linkLabel, "Tender 4471 — documents required")
    }

    /// A strip with no title is a strip nobody finds; a message with no subject still has a sender.
    func testAMessageWithNoSubjectIsStillGivenAName() {
        let plan = StripFromMail.plan(for: message(subject: "  "), body: nil, now: now)
        XCTAssertEqual(plan.title, "Email from Mona Salmeen")
    }

    func testABareAddressIsNotUsedAsAContactName() {
        let plan = StripFromMail.plan(for: message(sender: "noreply@example.com"), body: nil, now: now)
        XCTAssertEqual(plan.contactName, "")
        XCTAssertEqual(plan.contactEmail, "noreply@example.com")
    }

    func testTheNotesSayWhoAskedAndWhen() {
        let plan = StripFromMail.plan(for: message(), body: MailBody(text: "Please send the papers."), now: now)
        XCTAssertTrue(plan.notes.contains("Mona Salmeen"), plan.notes)
        XCTAssertTrue(plan.notes.contains("Please send the papers."), plan.notes)
    }

    func testANewsletterIsNotPastedWholeOntoTheBoard() {
        let long = String(repeating: "word ", count: 2_000)
        let plan = StripFromMail.plan(for: message(), body: MailBody(text: long), now: now)
        XCTAssertTrue(plan.notes.count < StripFromMail.noteLimit + 200, "\(plan.notes.count)")
        XCTAssertTrue(plan.notes.hasSuffix("…"), String(plan.notes.suffix(10)))
    }

    // MARK: - The date the message is asking for

    func testADeadlineInTheMessageBecomesTheDueDate() throws {
        let body = MailBody(text: "Dear Sir,\n\nDocuments must be submitted by 15 October 2026.\n\nRegards")
        let plan = StripFromMail.plan(for: message(), body: body, now: now)
        let due = try XCTUnwrap(plan.dueAt)
        XCTAssertEqual(
            Calendar(identifier: .gregorian).dateComponents([.day, .month, .year], from: due),
            DateComponents(year: 2026, month: 10, day: 15)
        )
        XCTAssertEqual(plan.dueKind, .deadline)
    }

    /// An invoice's own issue date is not a due date.
    func testADateThatIsNotADeadlineIsNotUsed() {
        let body = MailBody(text: "Invoice date: 01 October 2026\nThank you for your business.")
        XCTAssertNil(StripFromMail.plan(for: message(), body: body, now: now).dueAt)
    }

    /// Last month's deadline on a strip made today is worse than no date at all.
    func testADeadlineThatHasAlreadyPassedIsLeftAlone() {
        let body = MailBody(text: "Payment was due by 15 March 2020.")
        XCTAssertNil(StripFromMail.plan(for: message(), body: body, now: now).dueAt)
    }

    func testAnAppointmentIsRecognisedAsOne() {
        let body = MailBody(text: "The meeting is on 14 October 2026 at the office.")
        XCTAssertEqual(StripFromMail.plan(for: message(), body: body, now: now).dueKind, .appointment)
    }

    /// A message with one date ahead of it and nothing labelling it is usually about that date.
    func testTheOnlyDateInAMessageIsTakenEvenWhenNothingLabelsIt() throws {
        let body = MailBody(text: "The office will be closed 14 October 2026.")
        let plan = StripFromMail.plan(for: message(), body: body, now: now)
        XCTAssertNotNil(plan.dueAt)
        XCTAssertEqual(plan.dueKind, .unknown)
        XCTAssertTrue(
            StripFromMail.logLine(for: plan).contains("the only date in it"),
            StripFromMail.logLine(for: plan)
        )
    }

    /// Two unlabelled dates and it's anybody's guess, so nothing is guessed.
    func testTwoUnlabelledDatesMeanNoDueDate() {
        let body = MailBody(text: "We met on 14 October 2026 and again on 20 October 2026.")
        XCTAssertNil(StripFromMail.plan(for: message(), body: body, now: now).dueAt)
    }

    func testAMessageWithNoDatesGetsNoDueDate() {
        let plan = StripFromMail.plan(for: message(), body: MailBody(text: "Thanks, noted."), now: now)
        XCTAssertNil(plan.dueAt)
        XCTAssertNil(plan.dueKind)
    }

    func testAnArabicDeadlineWorksTheSameWay() throws {
        let body = MailBody(text: "آخر موعد لتقديم المستندات: 15/10/2026")
        let plan = StripFromMail.plan(for: message(), body: body, now: now)
        XCTAssertNotNil(plan.dueAt)
        XCTAssertEqual(plan.dueKind, .deadline)
    }

    /// The log has to say where a date came from, or a due date nobody set looks like a bug.
    func testTheLogSaysWhereTheStripAndItsDateCameFrom() {
        let plain = StripFromMail.plan(for: message(), body: MailBody(text: "Noted."), now: now)
        XCTAssertEqual(StripFromMail.logLine(for: plain), "Filed from an email")

        let dated = StripFromMail.plan(
            for: message(), body: MailBody(text: "Due by 15 October 2026."), now: now
        )
        XCTAssertTrue(StripFromMail.logLine(for: dated).contains("due date read from it"), StripFromMail.logLine(for: dated))
    }
}
