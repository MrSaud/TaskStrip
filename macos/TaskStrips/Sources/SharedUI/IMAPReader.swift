import Foundation

/// Reads the inbox from every account that's been set up, and keeps the last list it got.
///
/// The only way the app reads mail, on all three platforms. The Mac used to ask Mail itself,
/// which needed no password and could reach Exchange — but only the Mac could do it, so the
/// inbox on the phone was a different inbox. One client against the servers is one list
/// everywhere, which is worth more than the accounts it costs.
///
/// The accounts are asked at the same time rather than one after another: eight accounts, each
/// a TLS handshake and a round trip or two, is a minute in a row and a couple of seconds at once.
@MainActor
final class IMAPReader: ObservableObject {
    static let shared = IMAPReader()

    @Published private(set) var messages: [MailMessage] = []
    @Published private(set) var problem: String?
    @Published private(set) var isReading = false

    private let store = IMAPAccountStore()
    private let cache = MailInboxCache(defaults: .standard, key: "imapInbox.last")
    private var lastRead: Date?

    /// Mail arrives all day; asking every few minutes is plenty and costs the server nothing.
    static let freshFor: TimeInterval = 5 * 60

    private init() {
        messages = cache.messages
        // Accounts used to live in this device's settings; they belong in the synced keychain
        // with their passwords. Nothing to do once it's done, on any device.
        _ = store.migrateLocalAccountsIfNeeded()
    }

    var hasAccounts: Bool { !store.accounts.isEmpty }

    func refresh(now: Date = .now, force: Bool = false) {
        guard hasAccounts else {
            messages = []
            problem = nil
            return
        }
        if !force, let lastRead, now.timeIntervalSince(lastRead) < Self.freshFor { return }
        guard !isReading else { return }
        isReading = true
        lastRead = now

        let accounts = store.accounts
        let passwords = accounts.reduce(into: [UUID: String]()) { result, account in
            result[account.id] = store.password(for: account)
        }

        Task {
            var collected: [MailMessage] = []
            var failures: [String] = []

            // Each account is a separate connection and none waits on another; the order they
            // come back in doesn't matter, since dates decide the list.
            await withTaskGroup(of: (String, Result<[MailMessage], Error>).self) { group in
                for account in accounts {
                    guard let password = passwords[account.id] else {
                        failures.append("\(account.name): no password saved")
                        continue
                    }
                    group.addTask {
                        do {
                            let read = try await IMAPConnection(account: account, password: password).fetchNewest()
                            // The server doesn't say whose mailbox this was; the account that
                            // asked does.
                            return (account.name, .success(read.map {
                                var message = $0
                                message.account = account.name
                                return message
                            }))
                        } catch {
                            return (account.name, .failure(error))
                        }
                    }
                }
                for await (name, outcome) in group {
                    switch outcome {
                    case .success(let read): collected += read
                    case .failure(let error): failures.append("\(name): \(error.localizedDescription)")
                    }
                }
            }

            // Merged rather than only sorted: the same message can arrive twice when one address
            // forwards to another, and both accounts are being read.
            let newest = MailInboxMerge.merged([collected])
            await MainActor.run {
                isReading = false
                if !newest.isEmpty {
                    messages = newest
                    cache.messages = newest
                }
                problem = failures.isEmpty ? nil : failures.joined(separator: "\n")
            }
        }
    }

    /// Tries an account before it's saved, so a wrong password is caught while someone is still
    /// looking at the field they typed it into.
    static func test(_ account: IMAPAccount, password: String) async -> String? {
        do {
            _ = try await IMAPConnection(account: account, password: password).fetchNewest(count: 1)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
