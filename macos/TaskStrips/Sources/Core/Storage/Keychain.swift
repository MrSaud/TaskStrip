import Foundation
import Security

/// A keychain, as a plain get/set/delete on a service and account.
///
/// There are two. The Mac's login keychain holds what belongs to this one machine: the Drive
/// client id and refresh token, and credential passwords from before Phase 2. iCloud Keychain
/// holds credential passwords now, so they reach the iPhone and iPad as well — end-to-end
/// encrypted by Apple, and never in the app's own store or in CloudKit.
///
/// Both want the same escape hatch for tests: an unsigned test host often can't reach the
/// keychain at all (errSecMissingEntitlement), and no test should be leaving items behind on
/// anyone's machine.
final class Keychain {
    enum Location {
        /// This Mac only. On iOS there is no login keychain; this is the device's own keychain.
        case local
        /// Synced through iCloud Keychain, readable by every app of the team in this group.
        case iCloud(accessGroup: String)
    }

    /// Shared by the Mac and iPhone/iPad apps. The team prefix is part of the name: the group
    /// is the team's, not one app's, which is why the Mac can keep its own bundle id and still
    /// read what the iPhone writes.
    static let sharedAccessGroup = "FZ332788BV.com.saud.taskstrip.shared"

    /// The one item the real-keychain check leaves behind, under "com.saud.taskstrip.integration-check",
    /// so a Debug build on another device can say whether it arrived.
    static let crossDeviceMarkerAccount = "cross-device-marker"

    private let isEphemeral: Bool
    private let location: Location
    private var memory: [String: String] = [:]

    /// The status of the last call that reached the Security framework, for a caller that needs
    /// to say why something failed — errSecMissingEntitlement reads very differently from
    /// errSecAuthFailed.
    private(set) var lastStatus: OSStatus = errSecSuccess

    init(ephemeral: Bool = false, location: Location = .local) {
        isEphemeral = ephemeral
        self.location = location
    }

    /// Follows the same launch argument everything else does.
    static let shared = Keychain(ephemeral: AppLaunch.isUITesting)

    static let iCloud = Keychain(ephemeral: AppLaunch.isUITesting, location: .iCloud(accessGroup: sharedAccessGroup))

    func value(service: String, account: String) -> String? {
        if isEphemeral { return memory[key(service, account)] }

        var query = baseQuery(service, account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        lastStatus = SecItemCopyMatching(query as CFDictionary, &item)
        guard lastStatus == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Nil or empty removes the item rather than storing a blank one.
    @discardableResult
    func set(_ value: String?, service: String, account: String) -> Bool {
        guard let value, !value.isEmpty else {
            remove(service: service, account: account)
            return true
        }
        if isEphemeral {
            memory[key(service, account)] = value
            return true
        }

        let data = Data(value.utf8)
        let query = baseQuery(service, account)
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            lastStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            return lastStatus == errSecSuccess
        }
        var insert = query
        insert[kSecValueData as String] = data
        if case .iCloud = location {
            // The strictest level a synced item may have: a ThisDeviceOnly item can't sync.
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        }
        lastStatus = SecItemAdd(insert as CFDictionary, nil)
        return lastStatus == errSecSuccess
    }

    func remove(service: String, account: String) {
        if isEphemeral {
            memory[key(service, account)] = nil
            return
        }
        lastStatus = SecItemDelete(baseQuery(service, account) as CFDictionary)
    }

    private func key(_ service: String, _ account: String) -> String { "\(service)/\(account)" }

    private func baseQuery(_ service: String, _ account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if case .iCloud(let group) = location {
            // On the Mac, synced items exist only in the data protection keychain — the iOS-style
            // one. Without this the query goes to the login keychain and never syncs.
            query[kSecUseDataProtectionKeychain as String] = true
            query[kSecAttrSynchronizable as String] = true
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
}
