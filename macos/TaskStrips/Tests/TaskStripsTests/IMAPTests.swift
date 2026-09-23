import XCTest
@testable import TaskStrips

final class IMAPCommandTests: XCTestCase {
    func testTheServerIsGuessedForTheProvidersMostPeopleUse() throws {
        XCTAssertEqual(try XCTUnwrap(IMAPHost.guess(for: "someone@icloud.com")).host, "imap.mail.me.com")
        XCTAssertEqual(try XCTUnwrap(IMAPHost.guess(for: "someone@gmail.com")).host, "imap.gmail.com")
        XCTAssertEqual(try XCTUnwrap(IMAPHost.guess(for: "SOMEONE@Yahoo.com")).host, "imap.mail.yahoo.com")
        XCTAssertEqual(try XCTUnwrap(IMAPHost.guess(for: "me@swapkuwait.com")).host, "imap.swapkuwait.com",
                       "the convention, offered rather than assumed")
        XCTAssertEqual(try XCTUnwrap(IMAPHost.guess(for: "me@icloud.com")).port, 993)
        XCTAssertNil(IMAPHost.guess(for: "not an address"))
    }

    /// Microsoft turned basic authentication off: a password is refused there however right it is.
    func testTheProvidersThatRefusePasswordsAreKnownInAdvance() {
        XCTAssertTrue(IMAPHost.refusesPasswords("me@outlook.com"))
        XCTAssertTrue(IMAPHost.refusesPasswords("me@hotmail.com"))
        XCTAssertFalse(IMAPHost.refusesPasswords("me@icloud.com"))
        XCTAssertTrue(IMAPHost.wantsAppPassword("me@gmail.com"))
        XCTAssertFalse(IMAPHost.wantsAppPassword("me@swapkuwait.com"))
    }

    func testAPasswordWithAQuoteInItDoesNotEndTheCommandEarly() {
        let command = IMAPCommand.login(tag: "a001", email: "me@example.com", password: "pa\"ss\\word")
        XCTAssertTrue(command.contains("\"pa\\\"ss\\\\word\""), command)
        XCTAssertTrue(command.hasSuffix("\r\n"))
    }

    func testTheNewestAreAskedForByTheirPlaceInTheMailbox() {
        // IMAP numbers messages oldest first, so the newest eight of 1000 are 993 through 1000.
        let command = IMAPCommand.fetchNewest(tag: "a003", total: 1000, count: 8)
        XCTAssertTrue(command.contains("FETCH 993:1000"), command)
        XCTAssertTrue(command.contains("BODY.PEEK"), "peeking leaves them unread")
    }

    func testAMailboxSmallerThanTheAskIsAskedForWhole() {
        XCTAssertTrue(IMAPCommand.fetchNewest(tag: "a003", total: 3, count: 8).contains("FETCH 1:3"))
    }

    func testTheReplyToACommandIsTheOneWearingItsTag() {
        let text = "* 42 EXISTS\r\na001 OK LOGIN completed\r\n"
        XCTAssertEqual(IMAPResponse.completion(for: "a001", in: text), .ok("LOGIN completed"))
        XCTAssertNil(IMAPResponse.completion(for: "a002", in: text), "not this command's reply")
        XCTAssertEqual(
            IMAPResponse.completion(for: "a001", in: "a001 NO [AUTHENTICATIONFAILED] Invalid credentials\r\n"),
            .no("[AUTHENTICATIONFAILED] Invalid credentials")
        )
    }

    func testTheMailboxSaysHowMuchItHolds() {
        XCTAssertEqual(IMAPResponse.exists(in: "* 1829 EXISTS\r\n* 3 RECENT\r\na002 OK\r\n"), 1829)
        XCTAssertNil(IMAPResponse.exists(in: "a002 OK\r\n"))
    }
}

final class IMAPHeadersTests: XCTestCase {
    func testTheFieldsAreReadOutOfTheHeaders() throws {
        let raw = """
        From: Ahmad Alenezi <ahmad@example.com>\r
        Subject: The quarterly figures\r
        Date: Mon, 21 Sep 2026 10:15:00 +0300\r
        Message-ID: <CAF123@mail.example.com>\r
        """
        let fields = IMAPHeaders.parse(raw)
        XCTAssertEqual(fields.subject, "The quarterly figures")
        XCTAssertEqual(fields.from, "Ahmad Alenezi <ahmad@example.com>")
        XCTAssertEqual(fields.messageID, "CAF123@mail.example.com", "without the brackets, as a link wants it")
        XCTAssertEqual(
            try XCTUnwrap(fields.date).timeIntervalSince1970,
            Date(timeIntervalSince1970: 1_789_974_900).timeIntervalSince1970,
            accuracy: 1
        )
    }

    /// Headers are ASCII, so an Arabic subject arrives encoded. Not decoding it would show
    /// gibberish on half this person's mail.
    func testAnEncodedSubjectComesBackAsWhatItSays() {
        XCTAssertEqual(
            IMAPHeaders.decodeWords("=?UTF-8?B?2YXYsdit2KjYpw==?="),
            "مرحبا"
        )
        XCTAssertEqual(
            IMAPHeaders.decodeWords("=?utf-8?Q?Caf=C3=A9_meeting?="),
            "Café meeting"
        )
        XCTAssertEqual(
            IMAPHeaders.decodeWords("Re: =?UTF-8?B?2YXYsdit2KjYpw==?= today"),
            "Re: مرحبا today",
            "an encoded word in the middle of plain text"
        )
        XCTAssertEqual(IMAPHeaders.decodeWords("Plain subject"), "Plain subject")
        XCTAssertEqual(IMAPHeaders.decodeWords("=?UTF-8?X?unknown?="), "=?UTF-8?X?unknown?=", "left as it is")
    }

    func testASubjectSplitAcrossLinesIsPutBackTogether() {
        let raw = "Subject: The quarterly\r\n figures for review\r\nFrom: a@example.com\r\n"
        XCTAssertEqual(IMAPHeaders.parse(raw).subject, "The quarterly figures for review")
    }

    func testEncodedWordsSplitAcrossLinesJoinWithoutAGap() {
        let raw = "Subject: =?UTF-8?B?2YXYsdit?=\r\n =?UTF-8?B?2KjYpw==?=\r\n"
        XCTAssertEqual(IMAPHeaders.parse(raw).subject, "مرحبا")
    }

    func testADateWithACommentStillReads() throws {
        let date = try XCTUnwrap(IMAPHeaders.date(from: "Mon, 21 Sep 2026 10:15:00 +0300 (AST)"))
        XCTAssertEqual(date.timeIntervalSince1970, 1_789_974_900, accuracy: 1)
        XCTAssertNil(IMAPHeaders.date(from: "whenever"))
    }
}

final class IMAPFetchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reply(headers: String, flags: String = "\\Seen") -> String {
        "* 12 FETCH (FLAGS (\(flags)) BODY[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)] {\(headers.utf8.count)}\r\n\(headers))\r\n"
    }

    func testAFetchReplyBecomesAMessage() throws {
        let headers = "From: Ahmad <ahmad@example.com>\r\nSubject: Figures\r\nMessage-ID: <x1@example.com>\r\nDate: Mon, 21 Sep 2026 10:15:00 +0300\r\n\r\n"
        let messages = IMAPFetch.messages(from: reply(headers: headers), now: now)

        XCTAssertEqual(messages.count, 1)
        let message = try XCTUnwrap(messages.first)
        XCTAssertEqual(message.subject, "Figures")
        XCTAssertEqual(message.senderName, "Ahmad")
        XCTAssertEqual(message.id, "x1@example.com")
        XCTAssertTrue(message.isRead)
    }

    func testAnUnseenMessageIsUnread() throws {
        let headers = "Subject: New\r\nFrom: a@example.com\r\n\r\n"
        let messages = IMAPFetch.messages(from: reply(headers: headers, flags: ""), now: now)
        XCTAssertEqual(messages.first?.isRead, false)
    }

    func testTheHeadersAreTakenByLengthRatherThanBySearching() throws {
        // A subject containing what looks like the end of a reply. Counting bytes is the only way
        // to read this correctly.
        let headers = "Subject: FETCH ( fake )\r\nFrom: a@example.com\r\n\r\n"
        let messages = IMAPFetch.messages(from: reply(headers: headers), now: now)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.subject, "FETCH ( fake )")
    }

    func testSeveralMessagesInOneReply() {
        let first = "Subject: One\r\nFrom: a@example.com\r\n\r\n"
        let second = "Subject: Two\r\nFrom: b@example.com\r\n\r\n"
        let messages = IMAPFetch.messages(from: reply(headers: first) + reply(headers: second), now: now)
        XCTAssertEqual(messages.map(\.subject), ["One", "Two"])
    }

    func testNonsenseIsNoMessage() {
        XCTAssertTrue(IMAPFetch.messages(from: "a004 OK FETCH completed\r\n", now: now).isEmpty)
        XCTAssertTrue(IMAPFetch.messages(from: "", now: now).isEmpty)
    }

    func testAMessageWithNoDateIsTakenAsJustNow() {
        let headers = "Subject: Undated\r\nFrom: a@example.com\r\n\r\n"
        XCTAssertEqual(IMAPFetch.messages(from: reply(headers: headers), now: now).first?.receivedAt, now)
    }
}
