import Foundation

/// One inbox out of several.
///
/// A Mac has two ways to read mail — Mail itself, and this app's own IMAP accounts — and the same
/// address is usually set up in both. Showing one source and hiding the other means an account
/// missing from the list for no visible reason; showing both means every Gmail message twice. So
/// the lists are merged and the duplicates dropped, which is what a person reading a board expects
/// either way.
enum MailInboxMerge {
    /// Every list as one, newest first, each message once.
    ///
    /// The earlier lists win a tie: a message read through Mail and through IMAP is the same
    /// message, and Mail's copy is the one whose link opens locally.
    static func merged(_ lists: [[MailMessage]], count: Int = MailInbox.count) -> [MailMessage] {
        var seen = Set<String>()
        var kept: [MailMessage] = []
        for message in lists.flatMap({ $0 }) {
            let id = message.id.trimmingCharacters(in: .whitespacesAndNewlines)
            // A message with no Message-ID can't be told apart from another; keeping it is the
            // lesser wrong, since dropping it loses mail that is genuinely there.
            if !id.isEmpty {
                guard seen.insert(id).inserted else { continue }
            }
            kept.append(message)
        }
        return MailInbox.newest(kept, count: count)
    }

    /// The accounts these messages came from, in alphabetical order, for the filter to offer.
    ///
    /// Only what's actually in the list: an account that has sent nothing lately is an entry that
    /// empties the pane when picked, which reads as a fault.
    static func accounts(in messages: [MailMessage]) -> [String] {
        var seen = Set<String>()
        for message in messages {
            guard let account = message.account?.trimmingCharacters(in: .whitespaces), !account.isEmpty else {
                continue
            }
            seen.insert(account)
        }
        return seen.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// What's left after the pane's filter. A nil account means all of them.
    static func filtered(_ messages: [MailMessage], account: String?, unreadOnly: Bool = false) -> [MailMessage] {
        messages.filter { message in
            if unreadOnly, message.isRead { return false }
            guard let account, !account.isEmpty else { return true }
            return message.account?.caseInsensitiveCompare(account) == .orderedSame
        }
    }
}
