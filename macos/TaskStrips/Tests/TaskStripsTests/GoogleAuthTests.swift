import XCTest
@testable import TaskStrips

/// Signing in with Google, for accounts that would rather not keep an app password.
final class GoogleAuthTests: XCTestCase {
    private let clientID = "123456-abcdef.apps.googleusercontent.com"

    /// Google's redirect for an installed app is its client id backwards.
    func testTheRedirectIsTheClientIdReversed() {
        XCTAssertEqual(
            GoogleAuth.redirectURI(clientID: clientID),
            "com.googleusercontent.apps.123456-abcdef:/oauth2redirect"
        )
    }

    func testSomethingThatIsNotAGoogleClientIdGivesNoRedirect() {
        XCTAssertEqual(GoogleAuth.redirectURI(clientID: "481f085f-4ccc-4494"), "")
        XCTAssertEqual(GoogleAuth.redirectURI(clientID: ""), "")
    }

    func testTheSignInAsksForWhatAMailClientNeeds() throws {
        let url = try XCTUnwrap(GoogleAuth.signInURL(clientID: clientID, verifier: "v", state: "s"))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(value("client_id"), clientID)
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge"), OAuthPKCE.challenge(for: "v"))
        XCTAssertTrue(try XCTUnwrap(value("scope")).contains("https://mail.google.com/"))
    }

    /// Without these two, the account works for an hour and then asks to sign in again forever:
    /// Google only hands over a refresh token when it's asked to.
    func testItAsksForSomethingThatLastsLongerThanAnHour() throws {
        let url = try XCTUnwrap(GoogleAuth.signInURL(clientID: clientID, verifier: "v", state: "s"))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "access_type" }?.value, "offline")
        XCTAssertEqual(items.first { $0.name == "prompt" }?.value, "consent")
    }

    func testTheCodeIsTakenOffTheRedirect() throws {
        let url = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123:/oauth2redirect?code=abc&state=s"))
        XCTAssertEqual(GoogleAuth.handoff(from: url, expecting: "s"), .code("abc"))
    }

    func testARedirectAnsweringSomebodyElsesRequestIsRefused() throws {
        let url = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123:/oauth2redirect?code=abc&state=other"))
        XCTAssertEqual(GoogleAuth.handoff(from: url, expecting: "s"), .wrongState)
    }

    func testGooglesOwnWordsAreKeptWhenItRefuses() throws {
        let url = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123:/oauth2redirect?error=access_denied&state=s"))
        XCTAssertEqual(GoogleAuth.handoff(from: url, expecting: "s"), .refused("access_denied"))
    }

    func testTheTokenRequestCarriesTheVerifierAndNoSecret() {
        let body = GoogleAuth.tokenRequestBody(clientID: clientID, code: "abc", verifier: "v")
        XCTAssertTrue(body.contains("code_verifier=v"), body)
        XCTAssertFalse(body.contains("client_secret"), "a secret in an app isn't a secret")
    }

    /// Whose mailbox it is comes back inside the id token, which saves asking separately.
    func testTheAddressIsReadOutOfTheIdToken() throws {
        let payload = try JSONSerialization.data(withJSONObject: ["email": "class.saud@gmail.com"])
        let token = "header." + OAuthPKCE.base64URL(payload) + ".signature"
        XCTAssertEqual(GoogleAuth.email(inIDToken: token), "class.saud@gmail.com")
    }

    func testSomethingThatIsNotATokenSaysNothing() {
        XCTAssertNil(GoogleAuth.email(inIDToken: "not-a-token"))
        XCTAssertNil(GoogleAuth.email(inIDToken: ""))
    }

    /// Google sends a refresh token once and not again; the one already held has to survive.
    func testARefreshKeepsTheRefreshTokenItAlreadyHas() throws {
        let renewed = try XCTUnwrap(
            OAuthTokens.read(["access_token": "new", "expires_in": 3_600], keepingRefresh: "old-refresh")
        )
        XCTAssertEqual(renewed.access, "new")
        XCTAssertEqual(renewed.refresh, "old-refresh")
        // And with nothing to keep, there's nothing to make an account out of.
        XCTAssertNil(OAuthTokens.read(["access_token": "new"]))
    }
}

/// Signing in to IMAP and SMTP with a token instead of a password.
final class XOAUTH2Tests: XCTestCase {
    func testTheSignInLineIsBuiltWithTheControlCharactersItNeeds() throws {
        let built = XOAUTH2.token(email: "me@gmail.com", accessToken: "ya29.abc")
        let decoded = try XCTUnwrap(Data(base64Encoded: built).map { String(decoding: $0, as: UTF8.self) })
        let one = String(UnicodeScalar(1))
        XCTAssertEqual(decoded, "user=me@gmail.com\(one)auth=Bearer ya29.abc\(one)\(one)")
        // A space where a control character belongs is a sign-in that fails with nothing to see.
        XCTAssertFalse(decoded.contains("auth=Bearer ya29.abc "), decoded)
    }

    func testTheImapCommandCarriesItsTag() {
        let command = XOAUTH2.imapCommand(tag: "a002", email: "me@gmail.com", accessToken: "t")
        XCTAssertTrue(command.hasPrefix("a002 AUTHENTICATE XOAUTH2 "), command)
        XCTAssertTrue(command.hasSuffix("\r\n"), "every IMAP command ends the line")
    }

    func testTheSmtpCommandIsTheSameStringAfterAuth() {
        let command = XOAUTH2.smtpCommand(email: "me@gmail.com", accessToken: "t")
        XCTAssertTrue(command.hasPrefix("AUTH XOAUTH2 "), command)
        XCTAssertTrue(command.contains(XOAUTH2.token(email: "me@gmail.com", accessToken: "t")))
    }

    func testAnAccountKnowsWhatItSignsInWith() {
        let google = IMAPAccount.google(email: "me@gmail.com")
        XCTAssertTrue(google.signsInWithGoogle)
        XCTAssertTrue(google.usesToken)
        XCTAssertEqual(google.host, "imap.gmail.com", "still IMAP — Google answers it")
        XCTAssertEqual(google.outgoingHost, "smtp.gmail.com")

        let appPassword = IMAPAccount(email: "me@gmail.com", host: "imap.gmail.com")
        XCTAssertFalse(appPassword.usesToken)
    }

    /// Accounts set up with an app password before any of this keep working exactly as they did.
    func testAnOlderAccountStillSignsInWithItsPassword() throws {
        let old = """
        {"id":"BF65B1C0-7587-4FB1-ADC4-539F42AB0938","email":"a@gmail.com","host":"imap.gmail.com","port":993,"label":""}
        """
        let account = try JSONDecoder().decode(IMAPAccount.self, from: Data(old.utf8))
        XCTAssertFalse(account.usesToken)
        XCTAssertFalse(account.signsInWithGoogle)
    }
}
