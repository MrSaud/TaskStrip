import CryptoKit
import XCTest
@testable import TaskStrips

/// Signing in to Microsoft without a secret, and reading what Graph sends back.
final class MicrosoftGraphTests: XCTestCase {
    // MARK: - The sign-in

    /// PKCE: the hash goes up first, the original stays here, and only whoever holds the original
    /// can finish. That's what makes a redirect back into an app safe with no client secret.
    func testTheChallengeIsTheHashOfTheVerifier() {
        let verifier = "a-known-verifier"
        let expected = MicrosoftGraph.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        XCTAssertEqual(MicrosoftGraph.challenge(for: verifier), expected)
    }

    func testBase64ForAUrlDropsThePaddingAndTheAwkwardCharacters() {
        let encoded = MicrosoftGraph.base64URL(Data([251, 255, 190]))
        XCTAssertFalse(encoded.contains("="), encoded)
        XCTAssertFalse(encoded.contains("+"), encoded)
        XCTAssertFalse(encoded.contains("/"), encoded)
    }

    func testEachSignInGetsItsOwnVerifier() {
        XCTAssertNotEqual(MicrosoftGraph.verifier(), MicrosoftGraph.verifier())
        XCTAssertGreaterThanOrEqual(MicrosoftGraph.verifier().count, 43, "PKCE's own minimum")
    }

    func testTheSignInAsksForWhatTheAppNeedsAndNoMore() throws {
        let url = try XCTUnwrap(MicrosoftGraph.signInURL(verifier: "v", state: "s"))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(value("client_id"), MicrosoftGraph.clientID)
        XCTAssertEqual(value("redirect_uri"), "msauth.com.saud.taskstrip://auth")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("response_type"), "code")
        let scope = try XCTUnwrap(value("scope"))
        XCTAssertTrue(scope.contains("Mail.Read"), scope)
        XCTAssertTrue(scope.contains("Mail.Send"), scope)
        XCTAssertTrue(scope.contains("offline_access"), scope)
        // Nothing broader: an app that asks for more than it needs is one an administrator refuses.
        XCTAssertFalse(scope.contains("Mail.ReadWrite"), scope)
        XCTAssertFalse(scope.contains(".All"), scope)
    }

    /// `common`, so whoever signs in brings their own organisation — the whole point of this
    /// route over IMAP.
    func testAnyOrganisationCanSignIn() {
        XCTAssertTrue(MicrosoftGraph.authorizeURL.contains("/common/"), MicrosoftGraph.authorizeURL)
    }

    func testTheCodeIsTakenOffTheRedirect() throws {
        let url = try XCTUnwrap(URL(string: "msauth.com.saud.taskstrip://auth?code=abc123&state=s"))
        XCTAssertEqual(MicrosoftGraph.handoff(from: url, expecting: "s"), .code("abc123"))
    }

    /// A redirect answering somebody else's request is not an answer to this one.
    func testARedirectWithTheWrongStateIsRefused() throws {
        let url = try XCTUnwrap(URL(string: "msauth.com.saud.taskstrip://auth?code=abc123&state=elsewhere"))
        XCTAssertEqual(MicrosoftGraph.handoff(from: url, expecting: "s"), .wrongState)
    }

    func testMicrosoftsOwnWordsAreKeptWhenItRefuses() throws {
        let url = try XCTUnwrap(
            URL(string: "msauth.com.saud.taskstrip://auth?error=access_denied&error_description=Admin%20consent%20required&state=s")
        )
        XCTAssertEqual(MicrosoftGraph.handoff(from: url, expecting: "s"), .refused("Admin consent required"))
    }

    func testTheTokenRequestCarriesTheVerifierAndNoSecret() {
        let body = MicrosoftGraph.tokenRequestBody(code: "abc", verifier: "v")
        XCTAssertTrue(body.contains("code_verifier=v"), body)
        XCTAssertTrue(body.contains("grant_type=authorization_code"), body)
        XCTAssertFalse(body.contains("client_secret"), "a secret in an app isn't a secret")
    }

    func testTokensAreReadWithTheirExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let tokens = try XCTUnwrap(
            MicrosoftGraph.tokens(from: ["access_token": "a", "refresh_token": "r", "expires_in": 3_600], now: now)
        )
        XCTAssertEqual(tokens.access, "a")
        XCTAssertTrue(tokens.isFresh(at: now))
        // Refreshed a minute early, so nothing expires while a request is in the air.
        XCTAssertFalse(tokens.isFresh(at: now.addingTimeInterval(3_570)))
    }

    func testAnAnswerWithNoTokensIsNotTokens() {
        XCTAssertNil(MicrosoftGraph.tokens(from: ["error": "invalid_grant"]))
        XCTAssertEqual(
            MicrosoftGraph.errorMessage(in: ["error": "invalid_grant", "error_description": "expired"]),
            "expired"
        )
        XCTAssertEqual(MicrosoftGraph.errorMessage(in: ["error": ["message": "Access denied"]]), "Access denied")
    }
}

/// What Graph sends, as the rest of the app understands it.
final class GraphMessageTests: XCTestCase {
    private var account: IMAPAccount { IMAPAccount.microsoft(email: "salenezi@kfas.org.kw") }

    private var listJSON: [String: Any] {
        [
            "value": [
                [
                    "id": "AAMkAGI2THE-LONG-GRAPH-ID",
                    "internetMessageId": "<abc123@kfas.org.kw>",
                    "subject": "Quarterly report",
                    "receivedDateTime": "2026-09-21T08:15:00Z",
                    "isRead": false,
                    "from": ["emailAddress": ["name": "Mona Salmeen", "address": "msalmeen@kfas.org.kw"]],
                    "toRecipients": [
                        ["emailAddress": ["name": "Saud", "address": "salenezi@kfas.org.kw"]],
                        ["emailAddress": ["address": "colleague@kfas.org.kw"]],
                    ],
                    "ccRecipients": [["emailAddress": ["address": "boss@kfas.org.kw"]]],
                ],
            ],
        ]
    }

    func testAMessageComesBackAsTheAppsOwnMessage() throws {
        let message = try XCTUnwrap(GraphMessages.messages(from: listJSON, account: account).first)
        XCTAssertEqual(message.subject, "Quarterly report")
        XCTAssertEqual(message.sender, "Mona Salmeen <msalmeen@kfas.org.kw>")
        XCTAssertEqual(message.senderAddress, "msalmeen@kfas.org.kw")
        XCTAssertFalse(message.isRead)
        XCTAssertEqual(message.account, "salenezi@kfas.org.kw")
    }

    /// The Message-ID is the id, so a link to this message is the same kind of link a dragged one
    /// leaves — and the same mail read twice is still one mail.
    func testTheMessageIdIsTheOneEveryOtherMailProgramUses() throws {
        let message = try XCTUnwrap(GraphMessages.messages(from: listJSON, account: account).first)
        XCTAssertEqual(message.id, "abc123@kfas.org.kw")
        XCTAssertEqual(message.link, "message://%3Cabc123@kfas.org.kw%3E")
        // And Graph's own id is kept, since fetching the body and replying both need it.
        XCTAssertEqual(message.remoteID, "AAMkAGI2THE-LONG-GRAPH-ID")
    }

    func testEverybodyElseOnTheMessageIsKeptForReplyingToAll() throws {
        let message = try XCTUnwrap(GraphMessages.messages(from: listJSON, account: account).first)
        XCTAssertEqual(
            MailAddress.list(in: message.to ?? ""),
            ["salenezi@kfas.org.kw", "colleague@kfas.org.kw"]
        )
        XCTAssertEqual(MailAddress.list(in: message.cc ?? ""), ["boss@kfas.org.kw"])
        XCTAssertTrue(MailDraft.hasOthers(message, mine: ["salenezi@kfas.org.kw"]))
    }

    func testAnHtmlBodyIsMadeReadableTheSameWayAnImapOneIs() {
        let body = GraphMessages.body(from: [
            "body": ["contentType": "html", "content": "<p>First.</p><p>Second &amp; last.</p>"],
        ])
        XCTAssertTrue(body.fromHTML)
        XCTAssertTrue(body.text.contains("Second & last."), body.text)
    }

    func testAPlainBodyIsLeftAsWritten() {
        let body = GraphMessages.body(from: ["body": ["contentType": "text", "content": "Just words."]])
        XCTAssertFalse(body.fromHTML)
        XCTAssertEqual(body.text, "Just words.")
    }

    func testFilesComeOffAMessageAsFiles() throws {
        let json: [String: Any] = [
            "value": [
                [
                    "@odata.type": "#microsoft.graph.fileAttachment",
                    "name": "invoice.pdf",
                    "contentType": "application/pdf",
                    "contentBytes": Data("%PDF-1.4".utf8).base64EncodedString(),
                    "isInline": false,
                ],
                // A message attached to a message is not bytes this app can put on a strip.
                ["@odata.type": "#microsoft.graph.itemAttachment", "name": "Forwarded note"],
            ],
        ]
        let files = GraphMessages.attachments(from: json)
        XCTAssertEqual(files.map(\.name), ["invoice.pdf"])
        XCTAssertEqual(files.first?.bytes, Data("%PDF-1.4".utf8))
    }

    // MARK: - Sending

    func testASentMessageCarriesEverybodyItIsAddressedTo() throws {
        let draft = MailDraft(
            from: "me@kfas.org.kw", to: "one@example.com", cc: "two@example.com, three@example.com",
            subject: "Hello", body: "Hi"
        )
        let payload = GraphMessages.sendPayload(draft)
        let message = try XCTUnwrap(payload["message"] as? [String: Any])
        XCTAssertEqual((message["toRecipients"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((message["ccRecipients"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(payload["saveToSentItems"] as? Bool, true, "Exchange files its own copy in Sent")
    }

    /// A styled signature has to be HTML, the same as over SMTP.
    func testASignatureMakesItAnHtmlMessage() throws {
        var draft = MailDraft(from: "me@kfas.org.kw", to: "one@example.com", subject: "Hello", body: "Hi")
        draft.signature = MailSignature(text: "Saud Alenezi", colorHex: "C1453B", size: 16)
        let message = try XCTUnwrap(GraphMessages.sendPayload(draft)["message"] as? [String: Any])
        let body = try XCTUnwrap(message["body"] as? [String: Any])
        XCTAssertEqual(body["contentType"] as? String, "html")
        XCTAssertTrue(try XCTUnwrap(body["content"] as? String).contains("color: #C1453B"))
    }

    func testAPlainMessageStaysPlain() throws {
        let draft = MailDraft(from: "me@kfas.org.kw", to: "one@example.com", subject: "Hello", body: "Hi")
        let message = try XCTUnwrap(GraphMessages.sendPayload(draft)["message"] as? [String: Any])
        XCTAssertEqual((message["body"] as? [String: Any])?["contentType"] as? String, "text")
    }

    /// Graph won't take an In-Reply-To header, so a reply is built from the original message —
    /// which is what puts it in the conversation.
    func testAReplyGoesThroughTheMessageItAnswers() {
        let id = "AAMkAGI2THE-LONG-GRAPH-ID"
        XCTAssertTrue(GraphMessages.replyDraftURL(id: id).hasSuffix("/createReply"), GraphMessages.replyDraftURL(id: id))
        XCTAssertTrue(GraphMessages.sendDraftURL(id: id).hasSuffix("/send"))
    }

    func testTheInboxIsAskedForNewestFirstAndHeadersOnly() {
        let url = GraphMessages.inboxURL(count: 15)
        XCTAssertTrue(url.contains("$top=15"), url)
        XCTAssertTrue(url.contains("receivedDateTime%20desc"), url)
        XCTAssertTrue(url.contains("$select="), url)
        XCTAssertFalse(url.contains("body"), "a list doesn't fetch bodies")
    }

    // MARK: - Accounts

    func testAMicrosoftAccountIsTellableApartFromAPasswordOne() {
        XCTAssertTrue(IMAPAccount.microsoft(email: "a@kfas.org.kw").signsInWithMicrosoft)
        XCTAssertFalse(IMAPAccount(email: "a@gmail.com", host: "imap.gmail.com").signsInWithMicrosoft)
    }

    /// Every account saved before Exchange was possible still decodes, as what it is.
    func testAnOlderAccountIsAPasswordAccount() throws {
        let old = """
        {"id":"BF65B1C0-7587-4FB1-ADC4-539F42AB0938","email":"a@gmail.com","host":"imap.gmail.com","port":993,"label":""}
        """
        let account = try JSONDecoder().decode(IMAPAccount.self, from: Data(old.utf8))
        XCTAssertNil(account.provider)
        XCTAssertFalse(account.signsInWithMicrosoft)
    }
}
