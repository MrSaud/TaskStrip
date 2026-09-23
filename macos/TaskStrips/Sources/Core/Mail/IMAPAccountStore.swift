import Foundation

/// The accounts the app reads mail from, and where their passwords live.
///
/// The account — address, server, port — is ordinary settings. The password goes to the same
/// iCloud keychain the credentials use, so an account set up on the Mac needs no second setup on
/// the phone, and the password is never in the app's own store, in a backup, or in CloudKit.
struct IMAPAccountStore {
    static let service = "com.saud.taskstrip.imap"

    private let defaults: UserDefaults
    private let keychain: Keychain
    private static let key = "imapAccounts"

    init(defaults: UserDefaults = .standard, keychain: Keychain = .iCloud) {
        self.defaults = defaults
        self.keychain = keychain
    }

    var accounts: [IMAPAccount] {
        get {
            guard let data = defaults.data(forKey: Self.key) else { return [] }
            return (try? JSONDecoder().decode([IMAPAccount].self, from: data)) ?? []
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.key)
        }
    }

    func password(for account: IMAPAccount) -> String? {
        keychain.value(service: Self.service, account: account.id.uuidString)
    }

    /// Adds or replaces an account. The password is written first: an account listed with no
    /// password behind it is an account that fails every time it's asked.
    @discardableResult
    func save(_ account: IMAPAccount, password: String) -> Bool {
        guard keychain.set(password, service: Self.service, account: account.id.uuidString) else { return false }
        var all = accounts
        if let index = all.firstIndex(where: { $0.id == account.id }) {
            all[index] = account
        } else {
            all.append(account)
        }
        accounts = all
        return true
    }

    func remove(_ account: IMAPAccount) {
        keychain.remove(service: Self.service, account: account.id.uuidString)
        accounts = accounts.filter { $0.id != account.id }
    }
}
