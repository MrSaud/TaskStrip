import XCTest
@testable import TaskStrips

/// Runs against the ephemeral store, never the real keychain.
///
/// Not a shortcut: an unsigned test host frequently can't reach the keychain at all
/// (errSecMissingEntitlement), and a test suite that wrote items into the runner's login keychain
/// — or a developer's — would be leaving litter behind on every run. What's checked here is the
/// contract every caller depends on; the SecItem calls behind it are exercised by using the app.
final class CredentialStoreTests: XCTestCase {
    private var store: CredentialStore!

    override func setUpWithError() throws {
        store = CredentialStore(ephemeral: true)
    }

    func testAPasswordComesBackForTheCredentialItWasSavedFor() {
        let id = UUID()
        XCTAssertTrue(store.setPassword("hunter2", for: id))
        XCTAssertEqual(store.password(for: id), "hunter2")
        XCTAssertTrue(store.hasPassword(for: id))
    }

    func testACredentialWithNothingSavedHasNoPassword() {
        XCTAssertNil(store.password(for: UUID()))
        XCTAssertFalse(store.hasPassword(for: UUID()))
    }

    func testTwoCredentialsDoNotShareAPassword() {
        let first = UUID()
        let second = UUID()
        store.setPassword("first", for: first)
        store.setPassword("second", for: second)

        XCTAssertEqual(store.password(for: first), "first")
        XCTAssertEqual(store.password(for: second), "second")
    }

    func testSavingAgainReplacesTheOldPassword() {
        let id = UUID()
        store.setPassword("old", for: id)
        store.setPassword("new", for: id)
        XCTAssertEqual(store.password(for: id), "new")
    }

    /// A credential with no password is a normal thing to keep — a note of a username and a URL.
    /// Storing a blank one would read as a password you simply can't see.
    func testAnEmptyPasswordRemovesTheEntryRatherThanStoringNothing() {
        let id = UUID()
        store.setPassword("something", for: id)
        store.setPassword("", for: id)

        XCTAssertNil(store.password(for: id))
        XCTAssertFalse(store.hasPassword(for: id))
    }

    func testANilPasswordAlsoRemovesIt() {
        let id = UUID()
        store.setPassword("something", for: id)
        store.setPassword(nil, for: id)
        XCTAssertNil(store.password(for: id))
    }

    /// Deleting a credential has to take its secret with it, or the keychain accumulates
    /// passwords nothing in the app can reach or account for.
    func testRemovingTakesThePasswordAway() {
        let id = UUID()
        store.setPassword("hunter2", for: id)
        store.removePassword(for: id)
        XCTAssertNil(store.password(for: id))
    }

    func testRemovingSomethingThatWasNeverThereIsFine() {
        store.removePassword(for: UUID())
    }
}
