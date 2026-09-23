import SwiftData
import XCTest
@testable import TaskStrips

final class StripMailTests: XCTestCase {
    private func strip(
        _ title: String = "Renew the passport",
        notes: String = "",
        due: Date? = nil,
        priority: Priority = .high,
        progress: Int = 0,
        tags: [String] = [],
        links: [TaskLink] = [],
        contacts: [TaskContact] = []
    ) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: 0, priority: priority)
        task.notes = notes
        task.dueAt = due
        task.progress = progress
        task.tags = tags
        task.links = links
        task.contacts = contacts
        return task
    }

    // MARK: - An email linked to a strip

    /// The exact shape Mail puts on the pasteboard when a message is dragged out of it: one
    /// colon, no slashes, and the angle brackets already escaped.
    func testTheLinkMailActuallyHandsOverIsRecognised() {
        let dragged = "message:%3C1372329598.91023@mail.example.com%3E"
        XCTAssertTrue(StripMail.isMessageLink(dragged))
        XCTAssertEqual(StripMail.label(for: dragged), "Email message")
        XCTAssertNotNil(URL(string: dragged), "it has to survive being made into a URL")
    }

    func testAMessageLinkIsToldApartFromAWebPage() {
        XCTAssertTrue(StripMail.isMessageLink("message://%3C123@mail.example%3E"))
        XCTAssertTrue(StripMail.isMessageLink("mailto:someone@example.com"))
        XCTAssertTrue(StripMail.isMessageLink("MESSAGE://%3C9%3E"), "the scheme's case doesn't matter")
        XCTAssertFalse(StripMail.isMessageLink("https://example.com"))
        XCTAssertFalse(StripMail.isMessageLink("not a url at all"))
        XCTAssertFalse(StripMail.isMessageLink(""))
    }

    func testALinkedMessageIsCalledSomethingReadable() {
        XCTAssertEqual(StripMail.label(for: "message://%3C123@mail.example%3E"), "Email message")
        XCTAssertEqual(StripMail.label(for: "mailto:boss@example.com"), "Email boss@example.com")
        // A web link is its own label.
        XCTAssertEqual(StripMail.label(for: "https://example.com"), "https://example.com")
    }

    // MARK: - A strip sent as an email

    func testTheSubjectIsTheStripAndAStripWithNoTitleStillHasOne() {
        XCTAssertEqual(StripMail.subject(for: strip()), "Renew the passport")
        XCTAssertEqual(StripMail.subject(for: strip("")), "Task Strips")
    }

    func testTheBodyCarriesWhatTheStripSays() {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let task = strip(notes: "Booked for Tuesday.", due: due, progress: 40, tags: ["HOME"])
        let body = StripMail.body(for: task)

        XCTAssertTrue(body.contains("Priority: High"), body)
        XCTAssertTrue(body.contains("Progress: 40%"), body)
        XCTAssertTrue(body.contains("Tags: HOME"), body)
        XCTAssertTrue(body.contains("Booked for Tuesday."), body)
        XCTAssertTrue(body.hasSuffix("— Sent from Task Strips"), body)
    }

    func testAnEmptyStripSendsNoEmptyHeadings() {
        let body = StripMail.body(for: strip(priority: .normal))
        XCTAssertFalse(body.contains("Tags:"), body)
        XCTAssertFalse(body.contains("Links:"), body)
        XCTAssertFalse(body.contains("People:"), body)
        XCTAssertFalse(body.contains("Progress:"), body)
    }

    /// A message: link is an id inside one person's mail app. Sending it to someone else would be
    /// sending them a link that can only ever fail.
    func testALinkedEmailIsNotPassedOnToSomeoneElse() {
        let task = strip(links: [
            TaskLink(url: "https://example.com/form", label: "The form"),
            TaskLink(url: "message://%3C123@mail.example%3E", label: ""),
        ])
        let body = StripMail.body(for: task)
        XCTAssertTrue(body.contains("The form — https://example.com/form"), body)
        XCTAssertFalse(body.contains("message://"), body)
    }

    func testTheMailtoEscapesEverythingThatWouldBreakIt() throws {
        let url = try XCTUnwrap(StripMail.mailtoURL(subject: "Tea & biscuits", body: "One\nTwo & three"))
        let text = url.absoluteString
        XCTAssertTrue(text.hasPrefix("mailto:?"), text)
        XCTAssertFalse(text.contains("Tea & biscuits"), "an unescaped ampersand ends the subject")
        XCTAssertTrue(text.contains("%26"), text)
        XCTAssertTrue(text.contains("%0A") || text.contains("%0D"), "the line break survives")
    }

    // MARK: - The files that go with it

    func testTheFilesThatFitGoAndTheRestStayBehind() {
        let plan = StripMail.attachmentsThatFit([5_000_000, 30_000_000, 1_000], limit: 20 * 1024 * 1024)
        XCTAssertEqual(plan.sent, [0, 2])
        XCTAssertEqual(plan.left, [1])
    }

    func testFilesAreTakenInOrderUntilTheLimitIsReached() {
        let plan = StripMail.attachmentsThatFit([8, 8, 8], limit: 20)
        XCTAssertEqual(plan.sent, [0, 1])
        XCTAssertEqual(plan.left, [2])
    }

    func testAFileWithNoSizeIsNotSent() {
        let plan = StripMail.attachmentsThatFit([0, 10], limit: 100)
        XCTAssertEqual(plan.sent, [1])
        XCTAssertEqual(plan.left, [0])
    }

    func testTheBodySaysWhichFilesWereLeftBehind() {
        XCTAssertNil(StripMail.note(forFilesLeftBehind: []))
        XCTAssertEqual(
            StripMail.note(forFilesLeftBehind: ["video.mov"]),
            "\n(video.mov was too large to attach.)"
        )
        XCTAssertEqual(
            StripMail.note(forFilesLeftBehind: ["a.mov", "b.zip"]),
            "\n(a.mov, b.zip were too large to attach.)"
        )
    }

    // MARK: - An email dropped as a file

    private let sample = """
    From: someone@example.com
    To: me@example.com
    Subject: The quote
    Message-ID: <CAF123abc@mail.example.com>
    Date: Mon, 1 Sep 2026 10:00:00 +0300

    Message-ID: <not-this-one@example.com>
    The body of the email.
    """

    func testTheLinkBackToAMessageIsReadOutOfTheFile() throws {
        let link = try XCTUnwrap(StripMail.messageLink(fromEmail: sample))
        XCTAssertTrue(link.hasPrefix("message://"), link)
        XCTAssertTrue(link.contains("CAF123abc"), link)
        // The angle brackets have to be escaped or the URL ends at the first one.
        XCTAssertFalse(link.contains("<"), link)
        XCTAssertTrue(StripMail.isMessageLink(link))
    }

    /// Only the headers count. A message quoting another message's id in its body would otherwise
    /// link to the wrong email entirely.
    func testOnlyTheHeaderIsRead() throws {
        let link = try XCTUnwrap(StripMail.messageLink(fromEmail: sample))
        XCTAssertFalse(link.contains("not-this-one"), link)
    }

    func testAFileWithNoMessageIdLinksToNothing() {
        XCTAssertNil(StripMail.messageLink(fromEmail: "Subject: no id here\n\nbody"))
        XCTAssertNil(StripMail.messageLink(fromEmail: ""))
        // A malformed one is no id at all.
        XCTAssertNil(StripMail.messageLink(fromEmail: "Message-ID: 123\n\nbody"))
    }

    func testAnEmailFileIsToldApartFromAnyOtherFile() {
        XCTAssertTrue(StripMail.isEmailFile(URL(fileURLWithPath: "/tmp/The quote.eml")))
        XCTAssertTrue(StripMail.isEmailFile(URL(fileURLWithPath: "/tmp/x.EML")))
        XCTAssertFalse(StripMail.isEmailFile(URL(fileURLWithPath: "/tmp/report.pdf")))
    }
}
