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
    private let directory = MailDirectoryStore()
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
                    let password = passwords[account.id] ?? ""
                    // A Microsoft account keeps a token rather than a password; everyone else
                    // without one is an account that would fail every time it was asked.
                    guard account.signsInWithMicrosoft || !password.isEmpty else {
                        failures.append("\(account.name): no password saved")
                        continue
                    }
                    group.addTask {
                        do {
                            let read = try await Self.newest(from: account, password: password)
                            // The server doesn't say whose mailbox this was; the account that
                            // asked does.
                            return (account.name, .success(read.map {
                                var message = $0
                                message.account = account.name
                                message.accountID = account.id
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
            // Everyone on everything just read, so writing to them later is a tap rather than a
            // typed address. Learnt from what's already been fetched: no extra request, and it
            // stays on the device.
            let mine = accounts.map(\.email)
            let learnt = MailDirectory.learning(from: collected, into: directory.contacts, mine: mine)
            await MainActor.run {
                directory.contacts = learnt
                isReading = false
                if !newest.isEmpty {
                    messages = newest
                    cache.messages = newest
                }
                problem = failures.isEmpty ? nil : failures.joined(separator: "\n")
            }
        }
    }

    /// Whichever client this account speaks through.
    static func newest(from account: IMAPAccount, password: String) async throws -> [MailMessage] {
        if account.signsInWithMicrosoft {
            return try await GraphMailClient(account: account).fetchNewest()
        }
        return try await IMAPConnection(account: account, password: password).fetchNewest()
    }

    /// A message, or why it couldn't be read. Not `Result`: the failure here is a sentence for
    /// someone to read, not an error to be thrown further.
    enum Outcome {
        case success(MailBody)
        case failure(String)
    }

    /// The message itself, asked for when someone opens one.
    ///
    /// Not kept: a list of headers is small enough to cache, and a folder of everyone's mail on
    /// disk is a different thing to be responsible for. Re-opening a message asks again.
    ///
    /// The limit is what stops a phone downloading a slide deck to show two paragraphs. Asking
    /// for the whole message is a second, deliberate fetch, made when someone wants a file out
    /// of it.
    func body(for message: MailMessage, limit: Int = MailBodyParser.byteLimit) async -> Outcome {
        guard let accountID = message.accountID,
              let account = store.accounts.first(where: { $0.id == accountID }),
              let uid = message.uid ?? (message.remoteID == nil ? nil : 0)
        else {
            return .failure("This message was read before the app could ask for its text — refresh the inbox.")
        }
        guard account.signsInWithMicrosoft || store.password(for: account) != nil else {
            return .failure("No password saved for \(account.name).")
        }
        do {
            if account.signsInWithMicrosoft {
                guard let remoteID = message.remoteID else {
                    return .failure("This message was read before the app could ask for its text — refresh the inbox.")
                }
                return .success(try await GraphMailClient(account: account).fetchBody(remoteID: remoteID))
            }
            let password = store.password(for: account) ?? ""
            let body = try await IMAPConnection(account: account, password: password).fetchBody(uid: uid, limit: limit)
            return .success(body)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Sends a message, then files a copy where every other device will see it.
    ///
    /// The two are separate errands on purpose. Sending succeeded or it didn't; filing the copy
    /// can fail afterwards without un-sending anything, and the difference is worth saying to
    /// whoever pressed Send rather than calling the whole thing a failure.
    enum SendOutcome {
        case sent(filedIn: String?)
        case filingFailed(String)
        case failed(String)
    }

    func send(_ draft: MailDraft, from account: IMAPAccount, replyingTo remoteID: String? = nil) async -> SendOutcome {
        // Graph sends and files its own copy in Sent, so there's nothing to append afterwards —
        // and a reply goes through the message it answers, which is what threads it.
        if account.signsInWithMicrosoft {
            do {
                let client = GraphMailClient(account: account)
                if let remoteID {
                    try await client.reply(draft, to: remoteID)
                } else {
                    try await client.send(draft)
                }
                return .sent(filedIn: "Sent Items")
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        guard let password = store.password(for: account) else {
            return .failed("No password saved for \(account.name).")
        }
        let written: String
        do {
            written = try await SMTPConnection(
                host: account.outgoingHost,
                port: account.outgoingPort,
                email: account.email,
                password: password
            ).send(draft)
        } catch {
            return .failed(error.localizedDescription)
        }
        do {
            let mailbox = try await IMAPConnection(account: account, password: password)
                .appendToSent(written)
            return .sent(filedIn: mailbox)
        } catch {
            return .filingFailed(error.localizedDescription)
        }
    }

    /// Who to offer while an address is being typed.
    func suggestions(for typed: String, from account: IMAPAccount?, excluding already: [String]) -> [MailContact] {
        MailDirectory.suggestions(
            for: typed,
            in: directory.contacts,
            domain: account?.email.split(separator: "@").last.map(String.init),
            excluding: already
        )
    }

    /// The accounts that can send, which is all of them: every account here signs in with a
    /// password, and the outgoing server is the incoming one's twin.
    var accounts: [IMAPAccount] { store.accounts }

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
