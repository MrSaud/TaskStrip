import XCTest
@testable import TaskStrips

/// The one-time move of passwords from the Mac's login keychain into iCloud Keychain. Runs
/// against the ephemeral keychains, like CredentialStoreTests, and a throwaway defaults suite so
/// the "already moved" flag can't leak between tests or into the app.
final class CredentialMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: CredentialStore!

    override func setUpWithError() throws {
        suiteName = "CredentialMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = CredentialStore(ephemeral: true, defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testOldPasswordsAreMovedAndReadBackTheSame() {
        let first = UUID(), second = UUID()
        store.setLegacyPassword("first", for: first)
        store.setLegacyPassword("second", for: second)

        let report = store.migrate(ids: [first, second])

        XCTAssertEqual(report, .init(moved: 2))
        XCTAssertTrue(store.hasMigrated)
        XCTAssertEqual(store.password(for: first), "first")
        XCTAssertEqual(store.password(for: second), "second")
    }

    /// Before the move has run, a credential still has to show its password — from the old copy.
    func testAPasswordNotYetMovedIsStillReadable() {
        let id = UUID()
        store.setLegacyPassword("old", for: id)
        XCTAssertFalse(store.hasMigrated)
        XCTAssertEqual(store.password(for: id), "old")
    }

    /// Once moved, the stale copy must never answer: a password deleted on the iPhone would
    /// otherwise reappear on the Mac.
    func testAfterTheMoveTheOldCopyIsNeverReadAgain() {
        let id = UUID()
        store.setLegacyPassword("old", for: id)
        store.migrate(ids: [id])

        store.setPassword(nil, for: id)

        XCTAssertNil(store.password(for: id))
    }

    /// A password edited after Phase 2 shipped is newer than the old copy, so the old one must
    /// not overwrite it.
    func testAPasswordAlreadyInICloudKeychainIsKeptOverTheOldCopy() {
        let id = UUID()
        store.setLegacyPassword("old", for: id)
        store.setPassword("edited", for: id)

        let report = store.migrate(ids: [id])

        XCTAssertEqual(report, .init(alreadyMoved: 1))
        XCTAssertEqual(store.password(for: id), "edited")
    }

    func testACredentialWithoutAPasswordIsCountedNotFailed() {
        let report = store.migrate(ids: [UUID()])
        XCTAssertEqual(report, .init(noPassword: 1))
        XCTAssertTrue(report.isComplete)
    }

    /// Deleting before the move has run has to take the old copy too, or the fallback read
    /// brings the password straight back.
    func testRemovingBeforeTheMoveTakesTheOldCopyToo() {
        let id = UUID()
        store.setLegacyPassword("old", for: id)
        store.removePassword(for: id)
        XCTAssertNil(store.password(for: id))
    }

    func testASecondRunDoesNothing() {
        let id = UUID()
        store.setLegacyPassword("old", for: id)
        store.migrate(ids: [id])

        XCTAssertEqual(store.migrate(ids: [id]), .init())
    }
}
