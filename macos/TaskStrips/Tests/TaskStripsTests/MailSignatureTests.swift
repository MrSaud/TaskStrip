import XCTest
@testable import TaskStrips

/// The lines at the bottom of everything you send, and the two halves they force the message into.
final class MailSignatureTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_758_600_000)

    private var signature: MailSignature {
        MailSignature(
            text: "Saud Alenezi\nKFAS", colorHex: "C1453B", size: 16, family: .serif,
            isBold: true, isItalic: false
        )
    }

    private func draft(_ signature: MailSignature?) -> MailDraft {
        MailDraft(
            from: "me@example.com", to: "them@example.com", subject: "Hello",
            body: "The message itself.", signature: signature
        )
    }

    func testNoSignatureLeavesThePlainMessageAlone() {
        let rendered = draft(nil).rendered(now: when, messageID: "x@y")
        XCTAssertTrue(rendered.contains("Content-Type: text/plain; charset=utf-8"), rendered)
        XCTAssertFalse(rendered.contains("multipart"), rendered)
    }

    func testAnEmptySignatureIsNoSignature() {
        let rendered = draft(MailSignature(text: "   ")).rendered(now: when, messageID: "x@y")
        XCTAssertFalse(rendered.contains("multipart"), rendered)
    }

    /// A colour survives no other way, so a styled signature sends both halves.
    func testAStyledSignatureSendsBothHalves() {
        let rendered = draft(signature).rendered(now: when, messageID: "x@y")
        XCTAssertTrue(rendered.contains("Content-Type: multipart/alternative"), rendered)
        XCTAssertTrue(rendered.contains("Content-Type: text/plain"), rendered)
        XCTAssertTrue(rendered.contains("Content-Type: text/html"), rendered)
    }

    /// Whichever half a mail program shows, it has to say the same thing.
    func testBothHalvesCarryTheMessageAndTheSignature() throws {
        let rendered = draft(signature).rendered(now: when, messageID: "x@y")
        let parsed = MailBodyParser.read(Data(rendered.utf8))
        // The plain half is preferred when reading, which is where the round trip lands.
        XCTAssertFalse(parsed.fromHTML)
        XCTAssertTrue(parsed.text.contains("The message itself."), parsed.text)
        XCTAssertTrue(parsed.text.contains("Saud Alenezi"), parsed.text)
        XCTAssertTrue(parsed.text.contains("KFAS"), parsed.text)
    }

    /// Two dashes and a space: what every mail program reads as "the signature starts here".
    func testThePlainHalfMarksWhereTheSignatureStarts() {
        XCTAssertTrue(signature.plainText.hasPrefix("-- \n"), signature.plainText)
        XCTAssertEqual(MailSignature(text: "").plainText, "")
    }

    func testTheStyledHalfCarriesTheStyle() {
        let html = signature.html
        XCTAssertTrue(html.contains("font-size: 16px"), html)
        XCTAssertTrue(html.contains("color: #C1453B"), html)
        XCTAssertTrue(html.contains("Georgia"), html)
        XCTAssertTrue(html.contains("font-weight: bold"), html)
        XCTAssertFalse(html.contains("font-style: italic"), html)
        // Line breaks are breaks, not one run-on line.
        XCTAssertTrue(html.contains("Saud Alenezi<br>"), html)
    }

    /// A company name with an ampersand in it arrives as itself, not as markup.
    func testTheFourCharactersThatMeanSomethingElseAreEscaped() {
        let awkward = MailSignature(text: "Smith & Sons <the \"best\">")
        XCTAssertTrue(awkward.html.contains("Smith &amp; Sons &lt;the &quot;best&quot;&gt;"), awkward.html)
    }

    func testTheTypedMessageIsEscapedInTheHtmlHalfToo() {
        let html = MailDraft.htmlBody("5 < 6 & \"quoted\"", signature: signature)
        XCTAssertTrue(html.contains("5 &lt; 6 &amp; &quot;quoted&quot;"), html)
    }

    /// A boundary that turns up inside the message would cut it in half.
    func testTheBoundaryCannotCollideWithTheMessage() {
        let boundary = MailDraft.boundary(for: "abc123@taskstrips.local")
        XCTAssertTrue(boundary.hasPrefix("taskstrips-"), boundary)
        XCTAssertFalse(boundary.contains("@"), boundary)
        let rendered = draft(signature).rendered(now: when, messageID: "abc123@taskstrips.local")
        // Opened once per part, and closed once at the end.
        XCTAssertEqual(rendered.components(separatedBy: "--\(boundary)").count - 1, 3)
        XCTAssertTrue(rendered.hasSuffix("--\(boundary)--"), String(rendered.suffix(80)))
    }

    /// Arabic in a signature has to survive both halves.
    func testAnArabicSignatureComesBackAsArabic() throws {
        let arabic = MailSignature(text: "سعود العنزي\nمؤسسة الكويت للتقدم العلمي")
        let rendered = draft(arabic).rendered(now: when, messageID: "x@y")
        let parsed = MailBodyParser.read(Data(rendered.utf8))
        XCTAssertTrue(parsed.text.contains("سعود العنزي"), parsed.text)
    }

    /// An account saved before signatures existed still decodes, with none.
    func testAnOlderAccountHasNoSignature() throws {
        let old = """
        {"id":"BF65B1C0-7587-4FB1-ADC4-539F42AB0938","email":"a@gmail.com","host":"imap.gmail.com","port":993,"label":""}
        """
        let account = try JSONDecoder().decode(IMAPAccount.self, from: Data(old.utf8))
        XCTAssertNil(account.signature)
    }

    func testASignatureIsKeptWithTheAccountSoEveryDeviceHasIt() throws {
        let defaults = UserDefaults(suiteName: "MailSignatureTests")!
        defer { UserDefaults().removePersistentDomain(forName: "MailSignatureTests") }
        let store = IMAPAccountStore(defaults: defaults, keychain: Keychain(ephemeral: true))

        var account = IMAPAccount(email: "a@example.com", host: "imap.example.com")
        account.signature = signature
        XCTAssertTrue(store.save(account, password: "secret"))
        XCTAssertEqual(store.accounts.first?.signature, signature)
    }
}
