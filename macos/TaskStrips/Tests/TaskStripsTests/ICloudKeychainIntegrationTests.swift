import XCTest
@testable import TaskStrips

/// Against the real iCloud Keychain, with a throwaway item under its own service name. Skipped
/// unless asked for, because every other test stays off the real keychain:
///
///     TEST_RUNNER_TASKSTRIPS_REAL_KEYCHAIN=1 xcodebuild test … -only-testing:TaskStripsTests/ICloudKeychainIntegrationTests
///
/// What it proves is the part the ephemeral tests can't: that this build is signed so the data
/// protection keychain accepts a synchronizable item in the shared group.
final class ICloudKeychainIntegrationTests: XCTestCase {
    private let service = "com.saud.taskstrip.integration-check"

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["TASKSTRIPS_REAL_KEYCHAIN"] == "1",
            "Real-keychain check; set TEST_RUNNER_TASKSTRIPS_REAL_KEYCHAIN=1 to run it."
        )
    }

    func testASyncedItemCanBeWrittenReadAndRemoved() {
        let keychain = Keychain(location: .iCloud(accessGroup: Keychain.sharedAccessGroup))
        let account = UUID().uuidString
        defer { keychain.remove(service: service, account: account) }

        XCTAssertTrue(keychain.set("check", service: service, account: account),
                      "SecItemAdd failed with OSStatus \(keychain.lastStatus)")
        XCTAssertEqual(keychain.value(service: service, account: account), "check",
                       "SecItemCopyMatching failed with OSStatus \(keychain.lastStatus)")

        keychain.remove(service: service, account: account)
        XCTAssertNil(keychain.value(service: service, account: account))
    }

    /// Leaves one item behind on purpose, for a Debug build of the iPhone app to look for at
    /// launch: the proof that what the Mac writes reaches the other devices. It holds only the
    /// time it was written.
    func testLeaveAMarkerForTheOtherDevices() {
        let keychain = Keychain(location: .iCloud(accessGroup: Keychain.sharedAccessGroup))
        XCTAssertTrue(keychain.set(ISO8601DateFormatter().string(from: .now),
                                   service: service, account: Keychain.crossDeviceMarkerAccount),
                      "SecItemAdd failed with OSStatus \(keychain.lastStatus)")
    }
}
