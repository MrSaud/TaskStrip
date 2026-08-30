import Foundation
import Security

/// The login keychain, as a plain get/set/delete on a service and account.
///
/// Two things need it — credential passwords and the Drive refresh token — and both want the
/// same escape hatch for tests: an unsigned test host often can't reach the keychain at all
/// (errSecMissingEntitlement), and no test should be leaving items behind on anyone's machine.
final class Keychain {
    private let isEphemeral: Bool
    private var memory: [String: String] = [:]

    init(ephemeral: Bool = false) {
        isEphemeral = ephemeral
    }

    /// Follows the same launch argument everything else does.
    static let shared = Keychain(
        ephemeral: ProcessInfo.processInfo.arguments.contains(TaskStripsApp.uiTestingArgument)
    )

    func value(service: String, account: String) -> String? {
        if isEphemeral { return memory[key(service, account)] }

        var query = baseQuery(service, account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
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
            return SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            ) == errSecSuccess
        }
        var insert = query
        insert[kSecValueData as String] = data
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    func remove(service: String, account: String) {
        if isEphemeral {
            memory[key(service, account)] = nil
            return
        }
        SecItemDelete(baseQuery(service, account) as CFDictionary)
    }

    private func key(_ service: String, _ account: String) -> String { "\(service)/\(account)" }

    private func baseQuery(_ service: String, _ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
