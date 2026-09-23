import XCTest
@testable import TaskStrips

/// Writing a message the way a server expects to receive it.
final class MailDraftTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_758_600_000)

    private func draft(subject: String = "Hello", body: String = "Hello there.") -> MailDraft {
        MailDraft(from: "me@example.com", to: "them@example.com", subject: subject, body: body)
    }

    func testAMessageCarriesTheHeadersAMailServerNeeds() {
        let rendered = draft().rendered(now: when, messageID: "fixed@taskstrips.local")
        XCTAssertTrue(rendered.contains("From: me@example.com"), rendered)
        XCTAssertTrue(rendered.contains("To: them@example.com"), rendered)
        XCTAssertTrue(rendered.contains("Subject: Hello"), rendered)
        XCTAssertTrue(rendered.contains("Message-ID: <fixed@taskstrips.local>"), rendered)
        XCTAssertTrue(rendered.contains("MIME-Version: 1.0"), rendered)
        // Headers end at a blank line, and the body follows.
        XCTAssertTrue(rendered.contains("\r\n\r\nHello there."), rendered)
    }

    func testTheDateIsWrittenTheWayMailWritesDates() {
        let rendered = draft().rendered(now: when, messageID: "x@y")
        XCTAssertTrue(rendered.contains("Date: Tue, 23 Sep 2025"), rendered)
    }

    /// The name goes out as an encoded word, the same shape the inbox decodes coming in.
    func testANonEnglishSubjectIsEncodedAndSurvivesARoundTrip() {
        let rendered = draft(subject: "مرحبا").rendered(now: when, messageID: "x@y")
        XCTAssertTrue(rendered.contains("Subject: =?UTF-8?B?"), rendered)
        let subjectLine = rendered.split(separator: "\r\n").first { $0.hasPrefix("Subject:") } ?? ""
        let decoded = IMAPHeaders.decodeWords(String(subjectLine.dropFirst("Subject: ".count)))
        XCTAssertEqual(decoded, "مرحبا")
    }

    func testAnEnglishSubjectIsLeftAlone() {
        XCTAssertEqual(MailDraft.encodedWord("Invoice for July"), "Invoice for July")
    }

    /// What the body reader decodes, the draft has to write.
    func testTheBodyGoesOutAsQuotedPrintableAndComesBackTheSame() {
        let text = "Total: 50\u{20AC} — thanks"
        let rendered = draft(body: text).rendered(now: when, messageID: "x@y")
        XCTAssertTrue(rendered.contains("Content-Transfer-Encoding: quoted-printable"), rendered)
        let parsed = MailBodyParser.read(Data(rendered.utf8))
        XCTAssertEqual(parsed.text, text)
    }

    func testLongLinesAreFoldedSoNoLineIsTooLongForAMailServer() {
        let rendered = draft(body: String(repeating: "word ", count: 60)).rendered(now: when, messageID: "x@y")
        for line in rendered.split(separator: "\r\n") {
            XCTAssertLessThanOrEqual(line.count, 78, String(line))
        }
    }

    func testAnAddressIsCheckedBeforeAnythingIsSent() {
        XCTAssertTrue(MailDraft.looksLikeAnAddress("someone@example.com"))
        XCTAssertFalse(MailDraft.looksLikeAnAddress("someone"))
        XCTAssertFalse(MailDraft.looksLikeAnAddress("someone@example"))
        XCTAssertFalse(MailDraft.looksLikeAnAddress("two people@example.com"))
        XCTAssertFalse(MailDraft.looksLikeAnAddress(""))
        XCTAssertFalse(draft().isSendable == false)
    }

    // MARK: - Replies

    private var incoming: MailMessage {
        MailMessage(
            id: "original@example.com",
            subject: "Quarterly report",
            sender: "Ahmad Alenezi <ahmad@example.com>",
            receivedAt: when,
            isRead: true
        )
    }

    func testAReplyGoesBackToWhoeverWroteAndThreadsUnderTheirMessage() {
        let reply = MailDraft.reply(to: incoming, from: "me@example.com", body: MailBody(text: "The numbers."))
        XCTAssertEqual(reply.to, "ahmad@example.com")
        XCTAssertEqual(reply.subject, "Re: Quarterly report")
        XCTAssertEqual(reply.inReplyTo, "original@example.com")

        let rendered = reply.rendered(now: when, messageID: "x@y")
        XCTAssertTrue(rendered.contains("In-Reply-To: <original@example.com>"), rendered)
        // References is what most mail programs actually thread on.
        XCTAssertTrue(rendered.contains("References: <original@example.com>"), rendered)
    }

    func testAThreadDoesNotCollectReAfterRe() {
        XCTAssertEqual(MailDraft.replySubject("Re: Quarterly report"), "Re: Quarterly report")
        XCTAssertEqual(MailDraft.replySubject("RE: Quarterly report"), "RE: Quarterly report")
        XCTAssertEqual(MailDraft.replySubject(""), "Re:")
    }

    func testTheOriginalIsQuotedUnderRoomToWriteIn() {
        let reply = MailDraft.reply(to: incoming, from: "me@example.com", body: MailBody(text: "Line one.\nLine two."))
        XCTAssertTrue(reply.body.hasPrefix("\n\n"), "there should be somewhere to type")
        XCTAssertTrue(reply.body.contains("Ahmad Alenezi wrote:"), reply.body)
        XCTAssertTrue(reply.body.contains("> Line one."), reply.body)
        XCTAssertTrue(reply.body.contains("> Line two."), reply.body)
    }

    func testAVeryLongOriginalIsQuotedInPart() {
        let long = MailBody(text: String(repeating: "a", count: 5_000))
        let reply = MailDraft.reply(to: incoming, from: "me@example.com", body: long)
        XCTAssertTrue(reply.body.hasSuffix("> …\n"), String(reply.body.suffix(20)))
    }
}

/// The conversation with an outgoing server.
final class SMTPTests: XCTestCase {
    func testTheLastLineOfAReplyIsTheOneThatEndsIt() {
        // A server lists what it can do, one line per thing, before the line that finishes.
        let partial = "250-smtp.example.com at your service\r\n250-SIZE 35882577\r\n"
        XCTAssertNil(SMTPResponse.complete(in: partial))

        let whole = partial + "250 AUTH LOGIN PLAIN\r\n"
        let reply = SMTPResponse.complete(in: whole)
        XCTAssertEqual(reply?.code, 250)
        XCTAssertTrue(reply?.isPositive == true)
        XCTAssertEqual(reply?.text.contains("AUTH LOGIN PLAIN"), true)
    }

    func testARefusalIsRecognisedAsOne() {
        let reply = SMTPResponse.complete(in: "535 5.7.8 Username and Password not accepted\r\n")
        XCTAssertEqual(reply?.code, 535)
        XCTAssertFalse(reply?.isPositive == true)
        XCTAssertEqual(reply?.text, "5.7.8 Username and Password not accepted")
    }

    func testAskingForMoreIsNotARefusal() {
        let reply = SMTPResponse.complete(in: "354 Go ahead\r\n")
        XCTAssertTrue(reply?.wantsMore == true)
        XCTAssertTrue(reply?.isPositive == true)
    }

    /// A lone full stop ends the message, so a line that starts with one needs another in front
    /// of it — otherwise mail is truncated at the first line beginning with a dot.
    func testALineBeginningWithAFullStopCannotEndTheMessageEarly() {
        let body = SMTPCommand.body("First line\r\n. not the end\r\nLast line")
        XCTAssertTrue(body.contains("\r\n.. not the end\r\n"), body)
        XCTAssertTrue(body.hasSuffix("\r\n.\r\n"), body)
    }

    func testTheOutgoingServerIsTheIncomingOnesTwin() {
        XCTAssertEqual(SMTPHost.guess(forIMAPHost: "imap.gmail.com"), "smtp.gmail.com")
        XCTAssertEqual(SMTPHost.guess(forIMAPHost: "imap.mail.me.com"), "smtp.mail.me.com")
        XCTAssertEqual(SMTPHost.guess(forIMAPHost: "outlook.office365.com"), "smtp.office365.com")
        XCTAssertEqual(
            SMTPHost.guess(forIMAPHost: "imap.mail.us-east-1.awsapps.com"),
            "smtp.mail.us-east-1.awsapps.com"
        )
        XCTAssertEqual(SMTPHost.guess(forIMAPHost: "imap.kfas.org.kw"), "smtp.kfas.org.kw")
    }

    func testAnAccountSavedBeforeSendingExistedStillKnowsWhereToSend() throws {
        // No smtpHost in the stored JSON: it has to be worked out rather than come back nil.
        let old = """
        {"id":"BF65B1C0-7587-4FB1-ADC4-539F42AB0938","email":"a@gmail.com","host":"imap.gmail.com","port":993,"label":""}
        """
        let account = try JSONDecoder().decode(IMAPAccount.self, from: Data(old.utf8))
        XCTAssertEqual(account.outgoingHost, "smtp.gmail.com")
        XCTAssertEqual(account.outgoingPort, 465)
    }
}

/// Finding the Sent folder, which every provider names differently.
final class SentMailboxTests: XCTestCase {
    func testTheFolderTaggedSentWinsWhateverItIsCalled() {
        let listing = """
        * LIST (\\HasNoChildren) "/" "INBOX"\r
        * LIST (\\HasNoChildren \\Sent) "/" "[Gmail]/Sent Mail"\r
        * LIST (\\HasNoChildren \\Trash) "/" "[Gmail]/Bin"\r
        a002 OK Success\r

        """
        XCTAssertEqual(IMAPResponse.sentMailbox(in: listing), "[Gmail]/Sent Mail")
    }

    /// Older servers tag nothing, and then the name is all there is to go on.
    func testAServerThatTagsNothingIsMatchedByName() {
        let listing = """
        * LIST (\\HasNoChildren) "." "INBOX"\r
        * LIST (\\HasNoChildren) "." "Drafts"\r
        * LIST (\\HasNoChildren) "." "Sent Items"\r
        a002 OK\r

        """
        XCTAssertEqual(IMAPResponse.sentMailbox(in: listing), "Sent Items")
    }

    func testAnAccountWithNowhereToFileACopySaysSoRatherThanGuessing() {
        let listing = """
        * LIST (\\HasNoChildren) "/" "INBOX"\r
        * LIST (\\HasNoChildren) "/" "Archive"\r
        a002 OK\r

        """
        XCTAssertNil(IMAPResponse.sentMailbox(in: listing))
    }

    func testTheAppendCommandAnnouncesTheLengthAndQuotesTheName() {
        let command = IMAPCommand.append(tag: "a003", mailbox: "[Gmail]/Sent Mail", bytes: 412)
        XCTAssertEqual(command, "a003 APPEND \"[Gmail]/Sent Mail\" (\\Seen) {412}\r\n")
    }
}

/// Reading the people out of a header, which is where a comma in somebody's name does damage.
final class MailAddressTests: XCTestCase {
    func testTheAddressesInAHeaderAreFound() {
        XCTAssertEqual(
            MailAddress.list(in: "a@example.com, Ahmad <b@example.com> , c@example.com"),
            ["a@example.com", "b@example.com", "c@example.com"]
        )
    }

    /// The one that matters: "Alenezi, Ahmad" is one person, not two.
    func testANameWithACommaInItIsStillOnePerson() {
        let header = "\"Alenezi, Ahmad\" <ahmad@example.com>, sales@example.com"
        XCTAssertEqual(MailAddress.list(in: header), ["ahmad@example.com", "sales@example.com"])
    }

    func testTextThatIsNotAnAddressIsLeftOut() {
        XCTAssertEqual(MailAddress.list(in: "undisclosed-recipients:;"), [])
        XCTAssertEqual(MailAddress.list(in: ""), [])
    }

    func testTheSamePersonInDifferentCapitalsIsOnePerson() {
        XCTAssertTrue(MailAddress.same("Ahmad@Example.com", "ahmad@example.com"))
        XCTAssertEqual(
            MailAddress.without(["ME@example.com"], from: ["me@example.com", "a@example.com", "A@example.com"]),
            ["a@example.com"]
        )
    }
}

/// Replying to everyone, and copying people in.
final class ReplyAllTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_758_600_000)

    private func message(
        to: String? = "me@example.com, colleague@example.com",
        cc: String? = "boss@example.com",
        replyTo: String? = nil
    ) -> MailMessage {
        MailMessage(
            id: "original@example.com",
            subject: "Quarterly report",
            sender: "Ahmad <ahmad@example.com>",
            receivedAt: when,
            isRead: true,
            to: to,
            cc: cc,
            replyTo: replyTo
        )
    }

    func testAReplyToEveryoneKeepsEveryoneButMe() {
        let draft = MailDraft.replyAll(
            to: message(), from: "me@example.com", mine: ["me@example.com"], body: MailBody(text: "Original.")
        )
        XCTAssertEqual(draft.to, "ahmad@example.com")
        XCTAssertEqual(draft.cc, "colleague@example.com, boss@example.com")
        // Everyone the server is told to deliver to, sender included, me excluded.
        XCTAssertEqual(draft.recipients, ["ahmad@example.com", "colleague@example.com", "boss@example.com"])
    }

    func testTheSenderIsNotAlsoCopiedIn() {
        let message = message(to: "me@example.com, ahmad@example.com", cc: nil)
        let draft = MailDraft.replyAll(to: message, from: "me@example.com", mine: ["me@example.com"], body: nil)
        XCTAssertEqual(draft.to, "ahmad@example.com")
        XCTAssertEqual(draft.cc, "")
    }

    /// A message addressed to one person has nobody else on it, so Reply All is just Reply.
    func testReplyAllIsNotOfferedWhenThereIsNobodyElse() {
        let alone = message(to: "me@example.com", cc: nil)
        XCTAssertFalse(MailDraft.hasOthers(alone, mine: ["me@example.com"]))
        XCTAssertTrue(MailDraft.hasOthers(message(), mine: ["me@example.com"]))
    }

    /// A newsletter says where replies go, and it isn't the address it was sent from.
    func testAReplyGoesWhereTheSenderAskedItTo() {
        let list = message(replyTo: "list@example.com")
        XCTAssertEqual(list.replyAddress, "list@example.com")
        let draft = MailDraft.reply(to: list, from: "me@example.com", body: nil)
        XCTAssertEqual(draft.to, "list@example.com")
    }

    func testACopiedMessageCarriesItsCcHeaderAndGoesToEveryone() {
        let draft = MailDraft(
            from: "me@example.com", to: "one@example.com", cc: "two@example.com, three@example.com",
            subject: "Hello", body: "Hi"
        )
        let rendered = draft.rendered(now: when, messageID: "x@y")
        XCTAssertTrue(rendered.contains("Cc: two@example.com, three@example.com"), rendered)
        XCTAssertEqual(draft.recipients.count, 3)
    }

    func testNoCcMeansNoCcHeaderAtAll() {
        let rendered = MailDraft(from: "me@example.com", to: "one@example.com", subject: "Hi", body: "x")
            .rendered(now: when, messageID: "x@y")
        XCTAssertFalse(rendered.contains("Cc:"), rendered)
    }

    /// A typo in the Cc shouldn't be discovered by the server halfway through sending.
    func testABadAddressAnywhereStopsTheWholeThing() {
        var draft = MailDraft(from: "me@example.com", to: "one@example.com", subject: "Hi", body: "x")
        XCTAssertTrue(draft.isSendable)
        draft.cc = "two@example.com, notanaddress"
        XCTAssertFalse(draft.isSendable)
    }

    func testAMessageWithNobodyInToCannotBeSentEvenWithACc() {
        let draft = MailDraft(from: "me@example.com", to: "", cc: "two@example.com", subject: "Hi", body: "x")
        XCTAssertFalse(draft.isSendable)
    }

    /// Headers cached before the app could reply to everyone carry no To or Cc.
    func testAnOlderCachedMessageStillRepliesToTheSender() throws {
        let old = """
        [{"id":"a@x","subject":"Hi","sender":"A <a@x.com>","receivedAt":100,"isRead":true}]
        """
        let decoded = try JSONDecoder().decode([MailMessage].self, from: Data(old.utf8))
        let message = try XCTUnwrap(decoded.first)
        XCTAssertEqual(message.replyAddress, "a@x.com")
        XCTAssertFalse(MailDraft.hasOthers(message, mine: []))
    }

    /// The headers have to be asked for, or none of this has anything to work with.
    func testTheFetchAsksForTheHeadersAReplyAllNeeds() {
        let command = IMAPCommand.fetchNewest(tag: "a002", total: 100, count: 8)
        for header in ["TO", "CC", "REPLY-TO"] {
            XCTAssertTrue(command.contains(header), command)
        }
    }

    func testThoseHeadersAreReadOffTheWire() {
        let headers = """
        From: Ahmad <ahmad@example.com>\r
        To: "Alenezi, Saud" <me@example.com>, colleague@example.com\r
        Cc: boss@example.com\r
        Reply-To: list@example.com\r
        Subject: Quarterly report\r

        """
        let fields = IMAPHeaders.parse(headers)
        XCTAssertEqual(fields.replyTo, "list@example.com")
        XCTAssertEqual(MailAddress.list(in: fields.to), ["me@example.com", "colleague@example.com"])
        XCTAssertEqual(MailAddress.list(in: fields.cc), ["boss@example.com"])
    }
}
