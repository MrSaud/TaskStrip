import Foundation

/// Where credential passwords actually live: iCloud Keychain, one generic-password item per
/// credential, keyed by its id.
///
/// Not the SwiftData store, and not a file this app encrypts itself. Android encrypts its
/// password column under a Keystore key; Apple has somewhere purpose-built to put the secret —
/// and to carry it to the user's other devices, end-to-end encrypted — so it goes there and the
/// store keeps only the parts that aren't secret.
///
/// Before Phase 2 the Mac kept these in its login keychain, which doesn't sync. `migrate` copies
/// them across once. The old copies are left where they were, as a backup, until Android is
/// retired; they are only read from until the move has finished without a failure.
///
/// `ephemeral` swaps both keychains for dictionaries that die with the process — see Keychain,
/// which this is a thin naming layer over.
final class CredentialStore {
    /// What one run of `migrate` did. Counts only — never a password, not even in a log.
    struct MigrationReport: Equatable {
        /// Copied from the login keychain and read back identical from iCloud Keychain.
        var moved = 0
        /// Already in iCloud Keychain from an earlier run; nothing to do.
        var alreadyMoved = 0
        /// A credential with no password, which is a normal thing to keep.
        var noPassword = 0
        /// Couldn't be written, or read back different. The old copy is untouched; it's tried
        /// again on the next launch.
        var failed = 0

        var isComplete: Bool { failed == 0 }
    }

    private let service: String
    private let keychain: Keychain
    private let legacyService: String
    private let legacy: Keychain?
    private let defaults: UserDefaults

    private static let migratedKey = "credentials.movedToICloudKeychain"

    static let shared = CredentialStore(ephemeral: AppLaunch.isUITesting)

    init(
        ephemeral: Bool = false,
        service: String = "com.saud.taskstrip.credentials",
        legacyService: String = "com.saud.taskstrip.mac.credentials",
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.legacyService = legacyService
        self.defaults = defaults
        if ephemeral {
            keychain = Keychain(ephemeral: true)
            legacy = Keychain(ephemeral: true)
        } else {
            keychain = .iCloud
            #if os(macOS)
            legacy = .shared
            #else
            // Nothing on an iPhone or iPad predates iCloud Keychain.
            legacy = nil
            #endif
        }
    }

    /// Whether every old password has been moved and checked. Until then a password that isn't in
    /// iCloud Keychain yet is read from where it used to be; after, never — or a password deleted
    /// on another device would come back from the stale copy on this one.
    var hasMigrated: Bool {
        legacy == nil || defaults.bool(forKey: Self.migratedKey)
    }

    func password(for id: UUID) -> String? {
        if let value = keychain.value(service: service, account: id.uuidString) { return value }
        guard !hasMigrated else { return nil }
        return legacy?.value(service: legacyService, account: id.uuidString)
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
        return keychain.set(password, service: service, account: id.uuidString)
    }

    /// Takes the old copy too, when there is one: a deliberate delete must not be undone by the
    /// fallback read above.
    func removePassword(for id: UUID) {
        keychain.remove(service: service, account: id.uuidString)
        legacy?.remove(service: legacyService, account: id.uuidString)
    }

    func hasPassword(for id: UUID) -> Bool {
        password(for: id) != nil
    }

    /// Copies each credential's password from the login keychain into iCloud Keychain and reads it
    /// back to check. Safe to run on every launch: what's already there is left alone, and once a
    /// run completes with no failures it doesn't run again.
    ///
    /// On the Mac, reading an item another build of the app wrote can make macOS ask for the login
    /// password. That's the system's prompt, not this app's — so this must not run on the main
    /// thread, and it never sees the password that was typed.
    @discardableResult
    func migrate(ids: [UUID]) -> MigrationReport {
        var report = MigrationReport()
        guard let legacy, !hasMigrated else { return report }

        for id in ids {
            let account = id.uuidString
            let current = keychain.value(service: service, account: account)
            guard let old = legacy.value(service: legacyService, account: account) else {
                if current == nil { report.noPassword += 1 } else { report.alreadyMoved += 1 }
                continue
            }
            // Something already in iCloud Keychain was written after the move began, so it's the
            // newer of the two: keep it rather than overwrite it with the old copy.
            if current != nil {
                report.alreadyMoved += 1
                continue
            }
            if keychain.set(old, service: service, account: account),
               keychain.value(service: service, account: account) == old {
                report.moved += 1
            } else {
                report.failed += 1
            }
        }

        if report.isComplete { defaults.set(true, forKey: Self.migratedKey) }
        return report
    }

    /// For tests: put a password where the Mac used to keep it.
    func setLegacyPassword(_ password: String, for id: UUID) {
        legacy?.set(password, service: legacyService, account: id.uuidString)
    }
}
