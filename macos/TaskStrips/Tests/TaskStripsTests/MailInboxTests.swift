import XCTest
@testable import TaskStrips

final class MailInboxTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var reply: String {
        [
            "CAF123@mail.example.com\tThe quarterly figures\tAhmad Alenezi <ahmad@example.com>\t1799990000\tfalse",
            "B77@mail.example.com\t\tnotifications@example.com\t1799980000\ttrue",
        ].joined(separator: "\n") + "\n"
    }

    func testEachLineBecomesAMessage() throws {
        let messages = MailInbox.parse(reply, now: now)
        XCTAssertEqual(messages.count, 2)

        let first = try XCTUnwrap(messages.first)
        XCTAssertEqual(first.subject, "The quarterly figures")
        XCTAssertEqual(first.sender, "Ahmad Alenezi <ahmad@example.com>")
        XCTAssertEqual(first.receivedAt, Date(timeIntervalSince1970: 1_799_990_000))
        XCTAssertFalse(first.isRead)
        XCTAssertTrue(messages[1].isRead)
    }

    func testAMessageWithNoSubjectStillReadsAsSomething() {
        XCTAssertEqual(MailInbox.parse(reply, now: now)[1].subject, "(no subject)")
    }

    func testTheSenderIsShownByNameWhereThereIsOne() {
        let messages = MailInbox.parse(reply, now: now)
        XCTAssertEqual(messages[0].senderName, "Ahmad Alenezi")
        XCTAssertEqual(messages[1].senderName, "notifications@example.com", "an address with no name stays as it is")
    }

    /// The same link Mail hands over when a message is dragged out of it, so a message in this
    /// list can be filed onto a strip exactly as a dragged one is.
    func testAMessageCarriesTheLinkThatOpensIt() throws {
        let link = try XCTUnwrap(MailInbox.parse(reply, now: now).first?.link)
        XCTAssertTrue(link.hasPrefix("message://"), link)
        XCTAssertTrue(link.contains("CAF123"), link)
        XCTAssertFalse(link.contains("<"), "the brackets have to be escaped")
        XCTAssertTrue(EmailLink.isMessage(link))
    }

    func testNonsenseIsNoMessage() {
        XCTAssertTrue(MailInbox.parse("").isEmpty)
        XCTAssertTrue(MailInbox.parse("just some words\n").isEmpty, "too few fields to be a message")
        XCTAssertTrue(MailInbox.parse("one\ttwo\tthree\n").isEmpty)
    }

    func testAMessageWithNoDateIsTakenAsJustNow() {
        let messages = MailInbox.parse("id\tSubject\tsomeone@example.com\t\tfalse\n", now: now)
        XCTAssertEqual(messages.first?.receivedAt, now)
    }

    /// Only a Mac can read Mail, so only a Mac is offered the pane.
    func testTheInboxIsOfferedOnlyWhereItCanBeRead() {
        #if os(macOS)
        XCTAssertTrue(BoardPane.onThisPlatform.contains(.inbox))
        #else
        XCTAssertFalse(BoardPane.onThisPlatform.contains(.inbox))
        #endif
        XCTAssertEqual(BoardPanes.inbox.rawValue, 16, "the numbers are stored; they can't shift")
    }

    /// Mail hands them over in the order its mailbox holds them — the first one it offered on a
    /// real inbox was from 2014 — so the list sorts them itself.
    func testTheNewestAreShownFirstHoweverTheyArrive() {
        let older = MailMessage(
            id: "a", subject: "Old", sender: "a@example.com",
            receivedAt: Date(timeIntervalSince1970: 1_400_000_000), isRead: true
        )
        let newer = MailMessage(
            id: "b", subject: "New", sender: "b@example.com",
            receivedAt: Date(timeIntervalSince1970: 1_799_000_000), isRead: false
        )
        XCTAssertEqual(MailInbox.newest([older, newer]).map(\.subject), ["New", "Old"])
    }

    func testOnlyAGlanceIsShownHoweverManyArrive() {
        let many = (0..<40).map {
            MailMessage(
                id: "\($0)", subject: "Message \($0)", sender: "someone@example.com",
                receivedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double($0)), isRead: false
            )
        }
        let shown = MailInbox.newest(many)
        XCTAssertEqual(shown.count, MailInbox.count)
        XCTAssertEqual(shown.first?.subject, "Message 39", "the newest of them")
    }
}

/// Mail answers when it feels like it, so the pane keeps the last list it saw.
final class MailInboxCacheTests: XCTestCase {
    private func message(_ id: String, _ subject: String) -> MailMessage {
        MailMessage(
            id: id, subject: subject, sender: "someone@example.com",
            receivedAt: Date(timeIntervalSince1970: 1_799_000_000), isRead: false
        )
    }

    func testTheLastListSurvivesUntilTheNextOne() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "inbox-\(UUID().uuidString)"))
        let cache = MailInboxCache(defaults: defaults)
        XCTAssertTrue(cache.messages.isEmpty)

        let list = [message("a", "First"), message("b", "Second")]
        cache.messages = list
        XCTAssertEqual(cache.messages, list)
    }

    /// An empty answer is Mail having trouble, not an empty inbox — it mustn't wipe what's kept.
    func testAnEmptyListIsNotWorthKeeping() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "inbox-\(UUID().uuidString)"))
        let cache = MailInboxCache(defaults: defaults)
        cache.messages = [message("a", "First")]
        cache.messages = []
        XCTAssertTrue(cache.messages.isEmpty, "it clears rather than pretending, and the reader keeps what it has")
    }
}
