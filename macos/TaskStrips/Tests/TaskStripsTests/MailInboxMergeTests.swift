import XCTest
@testable import TaskStrips

/// Two sources, one list. The Mac reads mail through Mail and through its own IMAP accounts, and
/// the same address is usually set up in both.
final class MailInboxMergeTests: XCTestCase {
    private func message(
        _ id: String,
        at seconds: TimeInterval,
        account: String? = nil,
        isRead: Bool = true
    ) -> MailMessage {
        MailMessage(
            id: id,
            subject: "Subject \(id)",
            sender: "Someone <someone@example.com>",
            receivedAt: Date(timeIntervalSince1970: seconds),
            isRead: isRead,
            account: account
        )
    }

    func testTheSameMessageFromBothSourcesIsShownOnce() {
        let mail = [message("a@x", at: 200, account: "Class")]
        let server = [message("a@x", at: 200, account: "class.saud@gmail.com")]
        let merged = MailInboxMerge.merged([mail, server])
        XCTAssertEqual(merged.count, 1)
        // The first list wins the tie, and on a Mac that's Mail — whose links open locally.
        XCTAssertEqual(merged.first?.account, "Class")
    }

    func testBothListsSurviveTheMergeAndComeBackNewestFirst() {
        let merged = MailInboxMerge.merged([
            [message("old@x", at: 100), message("new@x", at: 900)],
            [message("middle@x", at: 500)],
        ])
        XCTAssertEqual(merged.map(\.id), ["new@x", "middle@x", "old@x"])
    }

    func testAMessageWithNoIdIsKeptRatherThanTakenForADuplicate() {
        let merged = MailInboxMerge.merged([
            [message("", at: 100), message("", at: 200)],
        ])
        XCTAssertEqual(merged.count, 2)
    }

    func testTheMergeStillStopsAtTheCount() {
        let many = (1...40).map { message("m\($0)@x", at: TimeInterval($0)) }
        XCTAssertEqual(MailInboxMerge.merged([many]).count, MailInbox.count)
    }

    func testOnlyAccountsThatActuallySentSomethingAreOffered() {
        let accounts = MailInboxMerge.accounts(in: [
            message("a@x", at: 1, account: "Work"),
            message("b@x", at: 2, account: "iCloud"),
            message("c@x", at: 3, account: "Work"),
            message("d@x", at: 4, account: ""),
            message("e@x", at: 5),
        ])
        XCTAssertEqual(accounts, ["iCloud", "Work"])
    }

    func testPickingAnAccountLeavesOnlyIts() {
        let messages = [
            message("a@x", at: 1, account: "Work"),
            message("b@x", at: 2, account: "iCloud"),
        ]
        XCTAssertEqual(MailInboxMerge.filtered(messages, account: "Work").map(\.id), ["a@x"])
        // Case is how it was typed, not how it was stored.
        XCTAssertEqual(MailInboxMerge.filtered(messages, account: "work").map(\.id), ["a@x"])
    }

    func testNoAccountMeansAllOfThem() {
        let messages = [message("a@x", at: 1, account: "Work"), message("b@x", at: 2)]
        XCTAssertEqual(MailInboxMerge.filtered(messages, account: nil).count, 2)
        XCTAssertEqual(MailInboxMerge.filtered(messages, account: "").count, 2)
    }

    func testUnreadOnlyHidesWhatHasBeenRead() {
        let messages = [
            message("a@x", at: 1, account: "Work", isRead: true),
            message("b@x", at: 2, account: "Work", isRead: false),
            message("c@x", at: 3, account: "iCloud", isRead: false),
        ]
        XCTAssertEqual(MailInboxMerge.filtered(messages, account: nil, unreadOnly: true).map(\.id), ["b@x", "c@x"])
        // Both narrowings at once.
        XCTAssertEqual(MailInboxMerge.filtered(messages, account: "Work", unreadOnly: true).map(\.id), ["b@x"])
    }

    /// The cache on disk was written before messages knew their account.
    func testACachedListFromTheOldFormatStillDecodes() throws {
        let old = """
        [{"id":"a@x","subject":"Hi","sender":"Someone","receivedAt":100,"isRead":true}]
        """
        let decoded = try JSONDecoder().decode([MailMessage].self, from: Data(old.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertNil(decoded.first?.account)
    }
}
