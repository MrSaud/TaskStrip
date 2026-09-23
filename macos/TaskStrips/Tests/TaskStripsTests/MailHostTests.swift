import XCTest
@testable import TaskStrips

/// Who runs a domain's mail, which the address itself often doesn't say.
final class MailHostTests: XCTestCase {
    func testGoogleWorkspaceIsRecognisedByItsMailExchanger() {
        XCTAssertEqual(MailHost.provider(forMailExchanger: "aspmx.l.google.com."), .google)
        XCTAssertEqual(MailHost.provider(forMailExchanger: "ALT1.ASPMX.L.GOOGLE.COM"), .google)
        XCTAssertEqual(MailHost.provider(forMailExchanger: "aspmx.l.google.com").imapHost, "imap.gmail.com")
    }

    /// The case that matters most: a domain that looks like a company running its own mail.
    func testAMicrosoftHostedDomainIsCaughtBeforeThePasswordIsTyped() {
        let provider = MailHost.provider(forMailExchanger: "kfas-org-kw.mail.protection.outlook.com")
        XCTAssertEqual(provider, .microsoft)
        XCTAssertEqual(provider.note?.contains("OAuth"), true)
    }

    func testWorkMailCarriesItsRegionInTheMailExchanger() {
        let provider = MailHost.provider(forMailExchanger: "inbound-smtp.us-east-1.amazonaws.com")
        XCTAssertEqual(provider, .amazonWorkMail(region: "us-east-1"))
        XCTAssertEqual(provider.imapHost, "imap.mail.us-east-1.awsapps.com")
        XCTAssertEqual(
            MailHost.provider(forMailExchanger: "inbound-smtp.ap-southeast-2.amazonaws.com").imapHost,
            "imap.mail.ap-southeast-2.awsapps.com"
        )
    }

    func testTheOtherProvidersThisAppKnows() {
        XCTAssertEqual(MailHost.provider(forMailExchanger: "mx01.mail.icloud.com"), .apple)
        XCTAssertEqual(MailHost.provider(forMailExchanger: "mta5.am0.yahoodns.net"), .yahoo)
        XCTAssertEqual(MailHost.provider(forMailExchanger: "mx.zoho.com"), .zoho)
    }

    func testSomeoneRunningTheirOwnMailIsLeftAlone() {
        let provider = MailHost.provider(forMailExchanger: "mail.example.org")
        XCTAssertEqual(provider, .unknown)
        XCTAssertNil(provider.imapHost)
        XCTAssertNil(provider.note)
    }

    // MARK: - The wire format

    /// Two bytes of preference, then a name written as length-prefixed labels.
    func testAnMXRecordIsReadOffTheWire() {
        var bytes: [UInt8] = [0, 10]
        for label in ["aspmx", "l", "google", "com"] {
            bytes.append(UInt8(label.count))
            bytes += Array(label.utf8)
        }
        bytes.append(0)
        let parsed = MXResolver.parse(Data(bytes))
        XCTAssertEqual(parsed?.preference, 10)
        XCTAssertEqual(parsed?.host, "aspmx.l.google.com")
    }

    func testATruncatedRecordIsRefusedRatherThanGuessedAt() {
        XCTAssertNil(MXResolver.parse(Data([0, 10, 5, 65, 66])))
        XCTAssertNil(MXResolver.parse(Data([0, 10])))
    }

    // MARK: - The form's own behaviour, without a network

    private struct StubResolver: MXResolving {
        let hosts: [String]
        func mailExchangers(for domain: String, timeout: TimeInterval) async -> [String] { hosts }
    }

    func testTheFormTakesDnsOverTheGuessByName() async {
        let found = await MailHost.best(
            for: "mr.saud@swapkuwait.com",
            resolver: StubResolver(hosts: ["inbound-smtp.us-east-1.amazonaws.com"])
        )
        // The guess by name would have been imap.swapkuwait.com, which doesn't exist.
        XCTAssertEqual(found.host, "imap.mail.us-east-1.awsapps.com")
        XCTAssertEqual(found.port, 993)
    }

    func testDnsThatSaysNothingLeavesTheGuessByName() async {
        let found = await MailHost.best(for: "someone@gmail.com", resolver: StubResolver(hosts: []))
        XCTAssertEqual(found.host, "imap.gmail.com")
        XCTAssertEqual(found.provider, .unknown)
    }

    func testAHostNobodyKnowsFallsBackRatherThanGuessingAProvider() async {
        let found = await MailHost.best(
            for: "someone@example.org",
            resolver: StubResolver(hosts: ["mail.example.org"])
        )
        XCTAssertEqual(found.host, "imap.example.org")
    }
}
