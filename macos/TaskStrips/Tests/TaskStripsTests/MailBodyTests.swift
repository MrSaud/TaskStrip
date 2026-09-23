import XCTest
@testable import TaskStrips

/// Getting the words out of a message. Almost nothing arrives as what someone typed.
final class MailBodyTests: XCTestCase {
    private func message(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
    }

    func testAPlainMessageIsItsOwnText() {
        let body = MailBodyParser.read(message("""
        From: someone@example.com
        Content-Type: text/plain; charset=utf-8

        Hello, and welcome.
        """))
        XCTAssertEqual(body.text, "Hello, and welcome.")
        XCTAssertFalse(body.fromHTML)
    }

    func testAMessageWithNoContentTypeIsReadAsPlainText() {
        let body = MailBodyParser.read(message("Subject: Hi\n\nJust text."))
        XCTAssertEqual(body.text, "Just text.")
    }

    func testQuotedPrintableIsPutBackTogether() {
        let body = MailBodyParser.read(message("""
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        This line was too long so it was =
        folded, and this costs =E2=82=AC5.
        """))
        XCTAssertEqual(body.text, "This line was too long so it was folded, and this costs \u{20AC}5.")
    }

    func testBase64IsDecoded() {
        let text = "Base sixty-four, decoded."
        let body = MailBodyParser.read(message("""
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: base64

        \(Data(text.utf8).base64EncodedString())
        """))
        XCTAssertEqual(body.text, text)
    }

    /// The charset that sent me looking: Arabic mail still arrives in windows-1256.
    func testArabicInAnOlderCharsetIsReadable() {
        var bytes = Data("Content-Type: text/plain; charset=windows-1256\r\n\r\n".utf8)
        // "مرحبا" as CP1256.
        bytes.append(contentsOf: [0xE3, 0xD1, 0xCD, 0xC8, 0xC7])
        XCTAssertEqual(MailBodyParser.read(bytes).text, "مرحبا")
    }

    func testTheTextVersionIsPreferredOverTheHtmlOne() {
        let body = MailBodyParser.read(message("""
        Content-Type: multipart/alternative; boundary="XYZ"

        --XYZ
        Content-Type: text/plain; charset=utf-8

        The words as typed.
        --XYZ
        Content-Type: text/html; charset=utf-8

        <html><body><p>The words as typed.</p></body></html>
        --XYZ--
        """))
        XCTAssertEqual(body.text, "The words as typed.")
        XCTAssertFalse(body.fromHTML)
    }

    func testHtmlIsUsedWhenThereIsNoPlainTextAndIsMadeReadable() {
        let body = MailBodyParser.read(message("""
        Content-Type: text/html; charset=utf-8

        <html><head><style>p { color: red }</style></head>
        <body><p>First paragraph.</p><p>Second &amp; last.</p>
        <script>alert('no')</script></body></html>
        """))
        XCTAssertTrue(body.fromHTML)
        XCTAssertTrue(body.text.contains("First paragraph."), body.text)
        XCTAssertTrue(body.text.contains("Second & last."), body.text)
        XCTAssertFalse(body.text.contains("color: red"), body.text)
        XCTAssertFalse(body.text.contains("alert"), body.text)
    }

    func testNumericEntitiesBecomeTheirCharacters() {
        XCTAssertEqual(MailBodyParser.decodingEntities(in: "&#1575;&#1604;&#1587;&#1604;&#1575;&#1605;"), "السلام")
        XCTAssertEqual(MailBodyParser.decodingEntities(in: "caf&#xe9;"), "café")
    }

    /// A newsletter is text wrapped around pictures; the pictures are not the message.
    func testAnAttachmentIsNotMistakenForTheMessage() {
        let body = MailBodyParser.read(message("""
        Content-Type: multipart/mixed; boundary="B"

        --B
        Content-Type: text/plain; charset=utf-8

        See the file.
        --B
        Content-Type: text/plain; charset=utf-8
        Content-Disposition: attachment; filename="notes.txt"

        Contents of the attachment.
        --B--
        """))
        XCTAssertEqual(body.text, "See the file.")
    }

    func testAMessageThatIsOnlyAnAttachmentHasNoText() {
        let body = MailBodyParser.read(message("""
        Content-Type: application/pdf; name="invoice.pdf"
        Content-Transfer-Encoding: base64

        JVBERi0xLjQK
        """))
        XCTAssertTrue(body.text.isEmpty)
    }

    func testNestedMultipartsAreLookedInside() {
        let body = MailBodyParser.read(message("""
        Content-Type: multipart/mixed; boundary="OUT"

        --OUT
        Content-Type: multipart/alternative; boundary="IN"

        --IN
        Content-Type: text/plain; charset=utf-8

        Buried two levels down.
        --IN--
        --OUT--
        """))
        XCTAssertEqual(body.text, "Buried two levels down.")
    }

    func testAMessageCutShortAtTheSizeLimitSaysSo() {
        let body = MailBodyParser.read(message("Content-Type: text/plain\n\nA long message"), wasTruncated: true)
        XCTAssertTrue(body.isTruncated)
        XCTAssertEqual(body.text, "A long message")
    }

    func testLayoutBlankLinesAreCollapsedButParagraphsSurvive() {
        XCTAssertEqual(MailBodyParser.tidied("One   \n\n\n\n\nTwo\n\nThree\n\n\n"), "One\n\nTwo\n\nThree")
    }

    // MARK: - What the server wraps it in

    func testTheLiteralIsTakenByItsByteCount() {
        var response = Data("* 12 FETCH (UID 99 BODY[] {11}\r\n".utf8)
        response.append(Data("Hello there".utf8))
        response.append(Data("\r\n)\r\na003 OK FETCH completed\r\n".utf8))
        XCTAssertEqual(IMAPFetch.literal(in: response).map { String(decoding: $0, as: UTF8.self) }, "Hello there")
    }

    func testTheUidComesBackWithTheHeaders() {
        let response = """
        * 12 FETCH (UID 43742 FLAGS (\\Seen) BODY[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)] {60}\r
        Subject: Hi\r
        From: A <a@b.com>\r
        Message-ID: <x@y>\r
        \r
        )\r
        a003 OK\r

        """
        let messages = IMAPFetch.messages(from: response)
        XCTAssertEqual(messages.first?.uid, 43742)
        XCTAssertEqual(messages.first?.isRead, true)
    }

    func testAReplyIsAddressedToTheSenderAlone() {
        let message = MailMessage(
            id: "x", subject: "Re: Hello", sender: "Ahmad Alenezi <ahmad@example.com>",
            receivedAt: .now, isRead: false
        )
        XCTAssertEqual(message.senderAddress, "ahmad@example.com")
        XCTAssertEqual(
            MailMessage(id: "x", subject: "s", sender: "plain@example.com", receivedAt: .now, isRead: false).senderAddress,
            "plain@example.com"
        )
        XCTAssertNil(
            MailMessage(id: "x", subject: "s", sender: "Nobody", receivedAt: .now, isRead: false).senderAddress
        )
    }
}

/// The files that come with a message, which are half of what a work inbox is for.
final class MailAttachmentTests: XCTestCase {
    private func message(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
    }

    private let invoice = Data("%PDF-1.4 a small pretend invoice".utf8)

    private func messageWithInvoice(disposition: String = "attachment; filename=\"invoice.pdf\"") -> Data {
        message("""
        Content-Type: multipart/mixed; boundary="B"

        --B
        Content-Type: text/plain; charset=utf-8

        The invoice is attached.
        --B
        Content-Type: application/pdf
        Content-Disposition: \(disposition)
        Content-Transfer-Encoding: base64

        \(invoice.base64EncodedString())
        --B--
        """)
    }

    func testAnAttachmentIsFoundBesideTheText() {
        let body = MailBodyParser.read(messageWithInvoice())
        XCTAssertEqual(body.text, "The invoice is attached.")
        XCTAssertEqual(body.attachments.count, 1)
        XCTAssertEqual(body.attachments.first?.name, "invoice.pdf")
        XCTAssertEqual(body.attachments.first?.type, "application/pdf")
        // The bytes are the file, decoded — not the base64 that carried it.
        XCTAssertEqual(body.attachments.first?.bytes, invoice)
    }

    func testCapitalsInAFilenameSurvive() {
        let body = MailBodyParser.read(messageWithInvoice(disposition: "attachment; filename=\"Invoice-July.PDF\""))
        XCTAssertEqual(body.attachments.first?.name, "Invoice-July.PDF")
    }

    /// An Arabic filename arrives either as an encoded word or as RFC 2231 percent-encoding.
    func testANonEnglishFilenameIsReadable() {
        let encodedWord = MailBodyParser.read(messageWithInvoice(
            disposition: "attachment; filename=\"=?UTF-8?B?2YXZhNmBLnBkZg==?=\""
        ))
        XCTAssertEqual(encodedWord.attachments.first?.name, "ملف.pdf")

        let extended = MailBodyParser.read(messageWithInvoice(
            disposition: "attachment; filename*=UTF-8''%D9%85%D9%84%D9%81.pdf"
        ))
        XCTAssertEqual(extended.attachments.first?.name, "ملف.pdf")
    }

    func testAFileWithNoNameIsNamedAfterWhatItIs() {
        let body = MailBodyParser.read(messageWithInvoice(disposition: "attachment"))
        XCTAssertEqual(body.attachments.first?.name, "attachment.pdf")
    }

    /// A signature logo is not what anyone means by an attachment, but it shouldn't vanish.
    func testInlineImagesComeLastAndSaySoS() {
        let body = MailBodyParser.read(message("""
        Content-Type: multipart/mixed; boundary="B"

        --B
        Content-Type: image/png
        Content-Disposition: inline; filename="logo.png"
        Content-Transfer-Encoding: base64

        \(Data("PNG".utf8).base64EncodedString())
        --B
        Content-Type: application/pdf
        Content-Disposition: attachment; filename="invoice.pdf"
        Content-Transfer-Encoding: base64

        \(invoice.base64EncodedString())
        --B--
        """))
        XCTAssertEqual(body.attachments.map(\.name), ["invoice.pdf", "logo.png"])
        XCTAssertEqual(body.attachments.first?.isInline, false)
        XCTAssertEqual(body.attachments.last?.isInline, true)
    }

    func testAPlainMessageHasNoAttachments() {
        XCTAssertTrue(MailBodyParser.read(message("Content-Type: text/plain\n\nJust words.")).attachments.isEmpty)
    }

    /// The text and HTML versions of a message are not files that came with it.
    func testTheAlternativeVersionsAreNotListedAsFiles() {
        let body = MailBodyParser.read(message("""
        Content-Type: multipart/alternative; boundary="A"

        --A
        Content-Type: text/plain; charset=utf-8

        Hello.
        --A
        Content-Type: text/html; charset=utf-8

        <p>Hello.</p>
        --A--
        """))
        XCTAssertTrue(body.attachments.isEmpty)
    }

    func testAttachedTextIsAFileRatherThanTheMessage() {
        let body = MailBodyParser.read(message("""
        Content-Type: multipart/mixed; boundary="B"

        --B
        Content-Type: text/plain; charset=utf-8

        See the notes.
        --B
        Content-Type: text/plain; charset=utf-8
        Content-Disposition: attachment; filename="notes.txt"

        The notes themselves.
        --B--
        """))
        XCTAssertEqual(body.text, "See the notes.")
        XCTAssertEqual(body.attachments.map(\.name), ["notes.txt"])
    }

    func testSizeIsSaidInSomethingAPersonReads() {
        let attachment = MailAttachment(name: "big.pdf", type: "application/pdf", bytes: Data(count: 412_000))
        XCTAssertTrue(attachment.size.contains("412"), attachment.size)
    }
}

/// Putting a file from a message onto a strip, which is the reason the inbox is here at all.
final class MailAttachmentFilingTests: XCTestCase {
    private var root: URL!
    private var store: AttachmentStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = AttachmentStore(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    func testBytesOutOfAMessageBecomeAFileOnDisk() throws {
        let bytes = Data("%PDF-1.4 invoice".utf8)
        let attachment = try store.add(bytes, named: "invoice.pdf")
        XCTAssertEqual(attachment.name, "invoice.pdf")
        XCTAssertEqual(attachment.kind, .document)
        XCTAssertEqual(try Data(contentsOf: store.url(for: attachment)), bytes)
    }

    func testAnImageIsFiledAsAnImage() throws {
        let attachment = try store.add(Data("PNG".utf8), named: "photo.png")
        XCTAssertEqual(attachment.kind, .image)
    }

    /// A filename out of a mail message is whatever the sender typed, including a slash.
    func testAFilenameCannotEscapeTheStore() throws {
        for name in ["../../escape.txt", "..", "/etc/passwd", ""] {
            let attachment = try store.add(Data("x".utf8), named: name)
            let written = store.url(for: attachment).standardizedFileURL.path
            XCTAssertTrue(written.hasPrefix(root.standardizedFileURL.path + "/"), written)
            XCTAssertTrue(FileManager.default.fileExists(atPath: written), written)
        }
    }

    func testTwoFilesOfTheSameNameDontOverwriteEachOther() throws {
        let first = try store.add(Data("one".utf8), named: "invoice.pdf")
        let second = try store.add(Data("two".utf8), named: "invoice.pdf")
        XCTAssertNotEqual(first.path, second.path)
        XCTAssertEqual(try Data(contentsOf: store.url(for: first)), Data("one".utf8))
        XCTAssertEqual(try Data(contentsOf: store.url(for: second)), Data("two".utf8))
    }
}
