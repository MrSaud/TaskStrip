import Foundation
import Security

/// Where credential passwords actually live: the login keychain, one generic-password item per
/// credential, keyed by its id.
///
/// Not the SwiftData store, and not a file this app encrypts itself. Android encrypts its
/// password column under a Keystore key; the Mac has somewhere purpose-built to put the secret,
/// so it goes there and the store keeps only the parts that aren't secret.
///
/// `ephemeral` swaps the keychain for a dictionary that dies with the process. UI tests and unit
/// tests both use it — an unsigned test host often can't reach the keychain at all
/// (errSecMissingEntitlement), and neither should be leaving items behind on anyone's machine.
final class CredentialStore {
    private let service: String
    private let isEphemeral: Bool
    private var memory: [UUID: String] = [:]

    static let shared: CredentialStore = {
        let underTest = ProcessInfo.processInfo.arguments.contains(TaskStripsApp.uiTestingArgument)
        return CredentialStore(ephemeral: underTest)
    }()

    init(ephemeral: Bool = false, service: String = "com.saud.taskstrip.mac.credentials") {
        self.isEphemeral = ephemeral
        self.service = service
    }

    func password(for id: UUID) -> String? {
        if isEphemeral { return memory[id] }

        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Setting an empty or nil password removes the item rather than storing a blank one — a
    /// credential with no password is a normal thing to keep, and an empty keychain entry would
    /// read as one that has a password you just can't see.
    @discardableResult
    func setPassword(_ password: String?, for id: UUID) -> Bool {
        guard let password, !password.isEmpty else {
            removePassword(for: id)
            return true
        }
        if isEphemeral {
            memory[id] = password
            return true
        }

        let data = Data(password.utf8)
        let query = baseQuery(for: id)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update = [kSecValueData as String: data]
            return SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        var insert = query
        insert[kSecValueData as String] = data
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    func removePassword(for id: UUID) {
        if isEphemeral {
            memory[id] = nil
            return
        }
        SecItemDelete(baseQuery(for: id) as CFDictionary)
    }

    func hasPassword(for id: UUID) -> Bool {
        password(for: id) != nil
    }

    private func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }
}
