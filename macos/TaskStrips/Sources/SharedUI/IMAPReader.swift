import Foundation

/// Reads the inbox from every account that's been set up, and keeps the last list it got.
///
/// This is the half that works on a phone: Mail can't be asked anything there, so the app asks
/// the server itself. On a Mac both are available, and the pane shows whichever is set up.
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

            for account in accounts {
                guard let password = passwords[account.id] else {
                    failures.append("\(account.name): no password saved")
                    continue
                }
                do {
                    let read = try await IMAPConnection(account: account, password: password).fetchNewest()
                    // The server doesn't say whose mailbox this was; the account that asked does.
                    collected += read.map { var message = $0; message.account = account.name; return message }
                } catch {
                    failures.append("\(account.name): \(error.localizedDescription)")
                }
            }

            let newest = MailInbox.newest(collected)
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
