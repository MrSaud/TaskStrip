import Foundation

/// The accounts the app reads mail from, and where their passwords live.
///
/// All of it goes to the iCloud keychain: the password because it's a password, and the account
/// beside it — address, server, port — because an account is no use on the phone without the
/// password, and a password is no use without the account. Set one up anywhere and every device
/// has it, which is the only way a list read from the servers can be the same list everywhere.
///
/// Nothing of this is in the app's own store, its backups, or CloudKit.
struct IMAPAccountStore {
    static let service = "com.saud.taskstrip.imap"
    /// The one item that holds the list. Not a UUID, so it can't collide with a password's.
    static let listAccount = "accounts"

    /// Kept as well as the keychain, and only read from: the keychain is the truth, and this is
    /// what the pane can show while iCloud is still waking up — or if the keychain refuses, which
    /// on an unsigned build it does.
    private let defaults: UserDefaults
    private let keychain: Keychain
    private static let key = "imapAccounts"

    init(defaults: UserDefaults = .standard, keychain: Keychain = .iCloud) {
        self.defaults = defaults
        self.keychain = keychain
    }

    var accounts: [IMAPAccount] {
        get {
            if let stored = keychain.value(service: Self.service, account: Self.listAccount),
               let decoded = try? JSONDecoder().decode([IMAPAccount].self, from: Data(stored.utf8)) {
                return decoded
            }
            // Either nothing has synced yet or the keychain wouldn't answer; the local copy is
            // the same list this device last saw.
            guard let data = defaults.data(forKey: Self.key) else { return [] }
            return (try? JSONDecoder().decode([IMAPAccount].self, from: data)) ?? []
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            keychain.set(String(decoding: data, as: UTF8.self), service: Self.service, account: Self.listAccount)
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

    /// Moves a list that predates the keychain into it, once.
    ///
    /// The accounts used to live in this device's settings only, which meant the phone couldn't
    /// see what the Mac had set up — and couldn't find the synced password either, since a
    /// re-typed account gets a new id. Called at launch; does nothing if there's nothing to move.
    @discardableResult
    func migrateLocalAccountsIfNeeded() -> Int {
        guard keychain.value(service: Self.service, account: Self.listAccount) == nil,
              let data = defaults.data(forKey: Self.key),
              let local = try? JSONDecoder().decode([IMAPAccount].self, from: data),
              !local.isEmpty
        else { return 0 }
        accounts = local
        return local.count
    }
}
