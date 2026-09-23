import XCTest
@testable import TaskStrips

/// Where the accounts live, which decides whether the phone has the same inbox as the Mac.
final class IMAPAccountStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var keychain: Keychain!
    private var store: IMAPAccountStore!
    private let suite = "IMAPAccountStoreTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
        // Ephemeral: an unsigned test host can't reach the real keychain, and no test should
        // leave items in anyone's.
        keychain = Keychain(ephemeral: true)
        store = IMAPAccountStore(defaults: defaults, keychain: keychain)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func account(_ email: String) -> IMAPAccount {
        IMAPAccount(email: email, host: "imap.example.com")
    }

    func testAnAccountIsSavedWhereEveryDeviceCanReadIt() {
        let one = account("a@example.com")
        XCTAssertTrue(store.save(one, password: "secret"))
        XCTAssertEqual(store.accounts.map(\.email), ["a@example.com"])
        // Not in the settings alone: the keychain is what syncs.
        XCTAssertNotNil(keychain.value(service: IMAPAccountStore.service, account: IMAPAccountStore.listAccount))
        XCTAssertEqual(store.password(for: one), "secret")
    }

    /// The phone reads what the Mac wrote — same keychain, its own settings.
    func testAnotherDeviceSeesTheAccountAndItsPassword() {
        let one = account("a@example.com")
        store.save(one, password: "secret")

        let phone = IMAPAccountStore(defaults: UserDefaults(suiteName: "\(suite).phone")!, keychain: keychain)
        XCTAssertEqual(phone.accounts, [one])
        XCTAssertEqual(phone.password(for: one), "secret")
        UserDefaults().removePersistentDomain(forName: "\(suite).phone")
    }

    func testSavingTheSameAccountAgainReplacesItRatherThanListingItTwice() {
        var one = account("a@example.com")
        store.save(one, password: "secret")
        one.host = "imap.elsewhere.com"
        store.save(one, password: "other")
        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.accounts.first?.host, "imap.elsewhere.com")
        XCTAssertEqual(store.password(for: one), "other")
    }

    func testRemovingAnAccountTakesItsPasswordWithIt() {
        let one = account("a@example.com")
        store.save(one, password: "secret")
        store.remove(one)
        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertNil(store.password(for: one))
    }

    func testAListFromBeforeTheKeychainIsMovedIntoItOnce() throws {
        let old = [account("old@example.com")]
        defaults.set(try JSONEncoder().encode(old), forKey: "imapAccounts")

        XCTAssertEqual(store.migrateLocalAccountsIfNeeded(), 1)
        XCTAssertEqual(store.accounts, old)
        // Again is a no-op, and doesn't resurrect an account deleted since.
        XCTAssertEqual(store.migrateLocalAccountsIfNeeded(), 0)
        store.remove(old[0])
        XCTAssertEqual(store.migrateLocalAccountsIfNeeded(), 0)
        XCTAssertTrue(store.accounts.isEmpty)
    }

    /// A keychain that won't answer — an unsigned build, iCloud Keychain off — still shows the
    /// list this device last saw rather than an empty pane.
    func testTheLocalCopyAnswersWhenTheKeychainCannot() throws {
        store.save(account("a@example.com"), password: "secret")
        let deaf = IMAPAccountStore(defaults: defaults, keychain: Keychain(ephemeral: true))
        XCTAssertEqual(deaf.accounts.map(\.email), ["a@example.com"])
    }
}
