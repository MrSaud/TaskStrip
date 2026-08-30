import XCTest
@testable import TaskStrips

/// The browser half of signing in can't be tested here — a consent screen needs a person. What
/// can be, and is, is everything around it: the PKCE maths, the URLs, and the parsing of what
/// Google sends back.
final class GoogleOAuthTests: XCTestCase {
    private let clientID = "123456-abcdef.apps.googleusercontent.com"

    /// RFC 7636's own worked example. Getting this wrong produces a token exchange that fails
    /// with "invalid_grant", which reads exactly like an expired code.
    func testThePKCEChallengeMatchesTheSpecsExample() {
        XCTAssertEqual(
            GoogleOAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    /// base64url, not base64: a "+" or "/" in the challenge is rejected, and padding is not
    /// allowed.
    func testTheChallengeIsUnpaddedBase64URL() {
        let challenge = GoogleOAuth.makePKCE().challenge
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertFalse(challenge.contains("="))
    }

    func testEachSignInGetsItsOwnVerifier() {
        XCTAssertNotEqual(GoogleOAuth.makePKCE().verifier, GoogleOAuth.makePKCE().verifier)
    }

    /// Google's convention for an iOS-type client: the client id reversed, used as a URL scheme.
    func testTheRedirectSchemeIsTheClientIDReversed() {
        XCTAssertEqual(
            GoogleOAuth.redirectScheme(for: clientID),
            "com.googleusercontent.apps.123456-abcdef"
        )
        XCTAssertEqual(
            GoogleOAuth.redirectURI(for: clientID),
            "com.googleusercontent.apps.123456-abcdef:/oauth2redirect"
        )
    }

    /// Anything else is caught before a browser opens, rather than failing several steps later
    /// with something unhelpful.
    func testSomethingThatIsNotAClientIDIsRejected() {
        XCTAssertNil(GoogleOAuth.redirectScheme(for: "123456-abcdef"))
        XCTAssertNil(GoogleOAuth.redirectScheme(for: ""))
        XCTAssertNil(GoogleOAuth.redirectURI(for: "not a client id"))
    }

    func testTheAuthorizationURLCarriesWhatGoogleNeeds() throws {
        let pkce = GoogleOAuth.makePKCE()
        let url = try XCTUnwrap(GoogleOAuth.authorizationURL(clientID: clientID, pkce: pkce))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(values["client_id"], clientID)
        XCTAssertEqual(values["response_type"], "code")
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["code_challenge"], pkce.challenge)
        // The scope Android asks for, and no more.
        XCTAssertEqual(values["scope"], "https://www.googleapis.com/auth/drive.file")
        // Without these two there's no refresh token, and it would ask for consent every hour.
        XCTAssertEqual(values["access_type"], "offline")
        XCTAssertEqual(values["prompt"], "consent")
    }

    // MARK: - Coming back from the browser

    func testTheCodeIsReadOutOfTheCallback() throws {
        let callback = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123:/oauth2redirect?code=abc123&scope=x"))
        XCTAssertEqual(try GoogleOAuth.authorizationCode(from: callback).get(), "abc123")
    }

    /// Declining consent comes back as a redirect, not an error — treating it as a failure would
    /// put an alert in front of someone who just changed their mind.
    func testADeclinedConsentIsACancellationRatherThanAFailure() throws {
        let callback = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123:/oauth2redirect?error=access_denied"))
        guard case .failure(let error) = GoogleOAuth.authorizationCode(from: callback) else {
            return XCTFail("a denied consent should not read as success")
        }
        XCTAssertEqual(error, .signInCancelled)
    }

    func testAnotherErrorIsReportedAsOne() throws {
        let callback = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123:/oauth2redirect?error=invalid_scope"))
        guard case .failure(let error) = GoogleOAuth.authorizationCode(from: callback) else {
            return XCTFail("an error should not read as success")
        }
        XCTAssertEqual(error, .signInFailed("invalid_scope"))
    }

    func testACallbackWithNothingUsefulInItFails() throws {
        let callback = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123:/oauth2redirect"))
        guard case .failure(let error) = GoogleOAuth.authorizationCode(from: callback) else {
            return XCTFail("an empty callback should not read as success")
        }
        XCTAssertEqual(error, .badCallback)
    }

    // MARK: - The token exchange

    func testTheTokenRequestIsAFormPost() throws {
        let request = try XCTUnwrap(
            GoogleOAuth.tokenRequest(clientID: clientID, code: "abc123", verifier: "v")
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")

        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=abc123"))
        XCTAssertTrue(body.contains("code_verifier=v"))
    }

    func testTheRefreshRequestAsksForARefresh() throws {
        let request = GoogleOAuth.refreshRequest(clientID: clientID, refreshToken: "r0")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        XCTAssertTrue(body.contains("refresh_token=r0"))
    }

    func testTokensAreReadOutOfTheReply() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let data = Data(#"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#.utf8)
        let tokens = try XCTUnwrap(GoogleOAuth.tokens(from: data, now: now))

        XCTAssertEqual(tokens.accessToken, "at")
        XCTAssertEqual(tokens.refreshToken, "rt")
        // A minute early on purpose — a token that expires mid-upload is worse than one refreshed
        // slightly sooner than it had to be.
        XCTAssertEqual(tokens.expiresAt, now.addingTimeInterval(3540))
    }

    /// A refresh reply carries no refresh token; the one already held stays good.
    func testARefreshReplyWithoutARefreshTokenIsStillValid() throws {
        let tokens = try XCTUnwrap(
            GoogleOAuth.tokens(from: Data(#"{"access_token":"at2","expires_in":3600}"#.utf8))
        )
        XCTAssertEqual(tokens.accessToken, "at2")
        XCTAssertNil(tokens.refreshToken)
    }

    func testAReplyWithNoAccessTokenIsNotTokens() {
        XCTAssertNil(GoogleOAuth.tokens(from: Data(#"{"error":"invalid_grant"}"#.utf8)))
        XCTAssertNil(GoogleOAuth.tokens(from: Data("not json".utf8)))
    }

    // MARK: - What's kept

    func testTheClientIDAndRefreshTokenRoundTripThroughTheKeychain() {
        let keychain = Keychain(ephemeral: true)
        XCTAssertNil(GoogleOAuth.clientID(keychain: keychain))

        GoogleOAuth.setClientID(clientID, keychain: keychain)
        GoogleOAuth.store(refreshToken: "rt", keychain: keychain)
        XCTAssertEqual(GoogleOAuth.clientID(keychain: keychain), clientID)
        XCTAssertEqual(GoogleOAuth.storedRefreshToken(keychain: keychain), "rt")

        GoogleOAuth.signOut(keychain: keychain)
        XCTAssertNil(GoogleOAuth.storedRefreshToken(keychain: keychain))
        // Signing out drops the token, not the setup — signing back in shouldn't mean pasting the
        // client id again.
        XCTAssertEqual(GoogleOAuth.clientID(keychain: keychain), clientID)
    }
}
