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

    /// The link that opens this message back in Mail.
    var link: String? {
        guard !id.isEmpty else { return nil }
        let escaped = "<\(id)>".addingPercentEncoding(
            withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~@"))
        )
        return escaped.map { "message://\($0)" }
    }

    /// "Ahmad Alenezi" out of "Ahmad Alenezi <ahmad@example.com>", which is how Mail hands the
    /// sender over. An address with no name in front of it stays as it is.
    var senderName: String {
        guard let bracket = sender.firstIndex(of: "<") else { return sender }
        let name = sender[..<bracket].trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\"")))
        return name.isEmpty ? sender : name
    }
}

/// Reads what Mail hands back. Kept apart from the asking so the shape of a line is pinned by a
/// test rather than by a mail app being open.
enum MailInbox {
    /// One message per line, tab-separated, because a subject can contain anything except a tab
    /// and a newline — which is why they're the separators rather than a comma or a colon.
    static let separator = "\t"

    static func parse(_ text: String, now: Date = .now) -> [MailMessage] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.components(separatedBy: separator)
            guard fields.count >= 5 else { return nil }
            let seconds = Double(fields[3].trimmingCharacters(in: .whitespaces))
            return MailMessage(
                id: fields[0].trimmingCharacters(in: .whitespaces),
                subject: fields[1].isEmpty ? "(no subject)" : fields[1],
                sender: fields[2],
                receivedAt: seconds.map { Date(timeIntervalSince1970: $0) } ?? now,
                isRead: fields[4].trimmingCharacters(in: .whitespaces).lowercased() == "true"
            )
        }
    }

    /// How many to show. Enough to see what's arrived since the last look, few enough to glance
    /// at beside a board.
    static let count = 15

    /// How many to ask Mail for before picking. Mail hands messages over in the order its mailbox
    /// holds them, which is not the order they arrived — the first one it offered here was from
    /// 2014 — so the last stretch is taken and sorted. Kept small: on a 30,000-message unified
    /// inbox, each property of a dozen messages costs Mail a couple of seconds.
    static let askFor = 8

    /// The newest first, however Mail happened to hand them over.
    static func newest(_ messages: [MailMessage], count: Int = count) -> [MailMessage] {
        Array(messages.sorted { $0.receivedAt > $1.receivedAt }.prefix(count))
    }
}

/// The last list Mail gave, kept so the pane has something to show the moment it opens.
///
/// Mail answers when it feels like it — on a thirty-thousand-message unified inbox the same
/// request took five seconds once and timed out at thirty the next — so the pane shows what it
/// last saw and quietly refreshes behind that, rather than making someone wait to see anything.
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
