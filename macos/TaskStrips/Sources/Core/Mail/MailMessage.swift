import Foundation

/// A message as the board needs to show it: who it's from, what it's about, when it came, and
/// whether it's been read. Nothing of the body — this is a list to glance at, not a mail client.
struct MailMessage: Identifiable, Equatable, Codable {
    /// The Message-ID, which is also what `message:` links point at — so a message in this list
    /// can be filed onto a strip exactly as one dragged out of Mail is.
    var id: String
    var subject: String
    var sender: String
    var receivedAt: Date
    var isRead: Bool
    /// Which account it arrived on: the one that asked for it. Older cached lists have none,
    /// which is why it's optional rather than blank.
    var account: String?
    /// The account's id and the message's UID in that account's inbox — between them, everything
    /// needed to go back and ask the server for the message itself.
    var accountID: UUID?
    var uid: Int?
    /// What the server calls this message where that isn't a number — Graph's own id, which is
    /// what fetching its body and replying to it both need.
    var remoteID: String?
    /// Who else it went to, and where the sender wants replies. Optional because a list cached
    /// before the app could reply to everyone doesn't carry them.
    var to: String?
    var cc: String?
    var replyTo: String?

    /// Where a reply goes: Reply-To when the sender named one, the From address otherwise.
    var replyAddress: String? {
        if let replyTo, let address = MailAddress.address(in: replyTo) { return address }
        return senderAddress
    }

    /// Everyone else on the message, with me and the person being replied to left out — the Cc
    /// line of a reply to everyone.
    func others(excluding mine: [String]) -> [String] {
        let everyone = MailAddress.list(in: to ?? "") + MailAddress.list(in: cc ?? "")
        return MailAddress.without(mine + [replyAddress].compactMap { $0 }, from: everyone)
    }

    /// The link that opens this message back in Mail.
    var link: String? {
        guard !id.isEmpty else { return nil }
        let escaped = "<\(id)>".addingPercentEncoding(
            withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~@"))
        )
        return escaped.map { "message://\($0)" }
    }

    /// "ahmad@example.com" out of "Ahmad Alenezi <ahmad@example.com>", for a reply to be
    /// addressed to. An address with no name around it is already the answer.
    var senderAddress: String? {
        if let open = sender.firstIndex(of: "<"), let close = sender[open...].firstIndex(of: ">") {
            let address = sender[sender.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            return address.contains("@") ? address : nil
        }
        let trimmed = sender.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") ? trimmed : nil
    }

    /// "Ahmad Alenezi" out of "Ahmad Alenezi <ahmad@example.com>", which is how Mail hands the
    /// sender over. An address with no name in front of it stays as it is.
    var senderName: String {
        guard let bracket = sender.firstIndex(of: "<") else { return sender }
        let name = sender[..<bracket].trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\"")))
        return name.isEmpty ? sender : name
    }
}

/// What the pane does with what a server hands back.
enum MailInbox {
    /// How many to show. Enough to see what's arrived since the last look, few enough to glance
    /// at beside a board.
    static let count = 15

    /// How many to ask each account for before picking. A mailbox holds its messages in arrival
    /// order, so the last stretch is the newest — taken, then sorted with every other account's.
    /// Kept small: it's a glance beside a board, and eight accounts asking at once.
    static let askFor = 8

    /// The newest first, however the servers happened to hand them over.
    static func newest(_ messages: [MailMessage], count: Int = count) -> [MailMessage] {
        Array(messages.sorted { $0.receivedAt > $1.receivedAt }.prefix(count))
    }
}

/// The last list the servers gave, kept so the pane has something to show the moment it opens.
///
/// Eight accounts over TLS is a few seconds at best, and a server that's having a bad morning is
/// longer — so the pane shows what it last saw and refreshes quietly behind it, rather than
/// making someone wait to see anything.
struct MailInboxCache {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "mailInbox.last") {
        self.defaults = defaults
        self.key = key
    }

    var messages: [MailMessage] {
        get {
            guard let data = defaults.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([MailMessage].self, from: data)) ?? []
        }
        nonmutating set {
            guard !newValue.isEmpty, let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: key)
                return
            }
            defaults.set(data, forKey: key)
        }
    }
}
