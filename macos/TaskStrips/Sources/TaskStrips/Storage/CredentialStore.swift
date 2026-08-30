import Foundation

/// Where credential passwords actually live: the login keychain, one generic-password item per
/// credential, keyed by its id.
///
/// Not the SwiftData store, and not a file this app encrypts itself. Android encrypts its
/// password column under a Keystore key; the Mac has somewhere purpose-built to put the secret,
/// so it goes there and the store keeps only the parts that aren't secret.
///
/// `ephemeral` swaps the keychain for a dictionary that dies with the process — see Keychain,
/// which this is now a thin naming layer over.
final class CredentialStore {
    private let service: String
    private let keychain: Keychain

    static let shared: CredentialStore = {
        let underTest = ProcessInfo.processInfo.arguments.contains(TaskStripsApp.uiTestingArgument)
        return CredentialStore(ephemeral: underTest)
    }()

    init(ephemeral: Bool = false, service: String = "com.saud.taskstrip.mac.credentials") {
        self.service = service
        self.keychain = ephemeral ? Keychain(ephemeral: true) : .shared
    }

    func password(for id: UUID) -> String? {
        keychain.value(service: service, account: id.uuidString)
    }

    /// Setting an empty or nil password removes the item rather than storing a blank one — a
    /// credential with no password is a normal thing to keep, and an empty keychain entry would
    /// read as one that has a password you just can't see.
    @discardableResult
    func setPassword(_ password: String?, for id: UUID) -> Bool {
        keychain.set(password, service: service, account: id.uuidString)
    }

    func removePassword(for id: UUID) {
        keychain.remove(service: service, account: id.uuidString)
    }

    func hasPassword(for id: UUID) -> Bool {
        password(for: id) != nil
    }
}
