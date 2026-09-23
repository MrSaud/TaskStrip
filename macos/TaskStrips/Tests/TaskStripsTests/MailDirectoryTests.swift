import XCTest
@testable import TaskStrips

/// Remembering who you write to, so nobody types an address twice.
final class MailDirectoryTests: XCTestCase {
    private func message(
        sender: String = "Ahmad <ahmad@kfas.org.kw>",
        to: String? = nil,
        cc: String? = nil,
        at seconds: TimeInterval = 1_000
    ) -> MailMessage {
        MailMessage(
            id: "\(seconds)@example.com",
            subject: "Subject",
            sender: sender,
            receivedAt: Date(timeIntervalSince1970: seconds),
            isRead: true,
            to: to,
            cc: cc
        )
    }

    func testEveryoneOnAMessageIsRemembered() {
        let learnt = MailDirectory.learning(
            from: [message(to: "me@kfas.org.kw, colleague@kfas.org.kw", cc: "Boss <boss@kfas.org.kw>")],
            into: [],
            mine: ["me@kfas.org.kw"]
        )
        XCTAssertEqual(
            Set(learnt.map(\.address)),
            ["ahmad@kfas.org.kw", "colleague@kfas.org.kw", "boss@kfas.org.kw"]
        )
        // My own address is not somebody to write to.
        XCTAssertFalse(learnt.contains { $0.address == "me@kfas.org.kw" })
    }

    func testANameIsKeptOnceOneArrives() {
        let first = MailDirectory.learning(from: [message(sender: "ahmad@kfas.org.kw")], into: [])
        XCTAssertEqual(first.first?.name, "")
        let second = MailDirectory.learning(from: [message(sender: "Ahmad Alenezi <ahmad@kfas.org.kw>")], into: first)
        XCTAssertEqual(second.first?.name, "Ahmad Alenezi")
        // And isn't lost again by a later message that carries no name.
        let third = MailDirectory.learning(from: [message(sender: "ahmad@kfas.org.kw")], into: second)
        XCTAssertEqual(third.first?.name, "Ahmad Alenezi")
    }

    func testSomeoneSeenOftenCountsForMore() {
        var known = MailDirectory.learning(from: [message(at: 100)], into: [])
        known = MailDirectory.learning(from: [message(at: 200)], into: known)
        XCTAssertEqual(known.first?.timesSeen, 2)
        XCTAssertEqual(known.first?.lastSeen, Date(timeIntervalSince1970: 200))
    }

    // MARK: - Who gets offered

    private let contacts = [
        MailContact(address: "colleague@kfas.org.kw", name: "Mona", lastSeen: .now, timesSeen: 2),
        MailContact(address: "supplier@elsewhere.com", name: "Monica", lastSeen: .now, timesSeen: 9),
        MailContact(address: "boss@kfas.org.kw", name: "Bassam", lastSeen: .now, timesSeen: 1),
    ]

    /// The people inside the same organisation come first: most mail is answered within the
    /// company it came from.
    func testColleaguesComeFirst() {
        let found = MailDirectory.suggestions(for: "", in: contacts, domain: "kfas.org.kw")
        XCTAssertEqual(found.prefix(2).map(\.address), ["colleague@kfas.org.kw", "boss@kfas.org.kw"])
    }

    func testWhatIsTypedNarrowsIt() {
        let found = MailDirectory.suggestions(for: "mon", in: contacts, domain: "kfas.org.kw")
        // Both match on name; the colleague wins the tie for being in the same organisation.
        XCTAssertEqual(found.map(\.address), ["colleague@kfas.org.kw", "supplier@elsewhere.com"])
    }

    func testAMatchAtTheStartBeatsOneInTheMiddle() {
        let found = MailDirectory.suggestions(for: "supplier", in: contacts, domain: nil)
        XCTAssertEqual(found.first?.address, "supplier@elsewhere.com")
    }

    /// Somebody already in the To line isn't a suggestion for the Cc line.
    func testPeopleAlreadyOnTheMessageAreNotOfferedAgain() {
        let found = MailDirectory.suggestions(
            for: "", in: contacts, domain: "kfas.org.kw", excluding: ["COLLEAGUE@kfas.org.kw"]
        )
        XCTAssertFalse(found.contains { $0.address == "colleague@kfas.org.kw" })
    }

    // MARK: - Typing

    func testPickingSomebodyCompletesTheHalfTypedOneAndLeavesTheRest() {
        XCTAssertEqual(
            MailDirectory.completing("one@example.com, mon", with: "colleague@kfas.org.kw"),
            "one@example.com, colleague@kfas.org.kw, "
        )
    }

    func testPickingSomebodyAfterACommaAddsThemRatherThanReplacingAnyone() {
        XCTAssertEqual(
            MailDirectory.completing("one@example.com, ", with: "two@example.com"),
            "one@example.com, two@example.com, "
        )
    }

    func testTheHalfTypedEntryIsWhatTheSuggestionsAreFor() {
        XCTAssertEqual(MailDirectory.partial(in: "one@example.com, mon"), "mon")
        XCTAssertEqual(MailDirectory.partial(in: "one@example.com, "), "")
        XCTAssertEqual(MailDirectory.partial(in: ""), "")
    }

    func testTheDirectoryDoesNotGrowForever() {
        let many = (1...600).map {
            message(sender: "person\($0)@example.com", at: TimeInterval($0))
        }
        XCTAssertEqual(MailDirectory.learning(from: many, into: []).count, MailDirectory.limit)
    }
}
