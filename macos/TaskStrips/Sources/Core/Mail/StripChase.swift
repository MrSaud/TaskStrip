import Foundation

/// Chasing the person a strip is waiting on.
///
/// The thing that actually slips in a project is the thing somebody else owes you. A strip already
/// knows who it's waiting on, since when, and how long is reasonable — but the chasing itself was
/// still a matter of remembering, opening a mail app, finding the original, and writing the same
/// polite paragraph again.
enum StripChase {
    /// Who to chase, worked out from the strip: the contact whose address matches the name being
    /// waited on, or the only contact there is.
    static func recipient(of task: TaskItem) -> TaskContact? {
        let waiting = task.waitingOnName.trimmingCharacters(in: .whitespaces).lowercased()
        let withAddresses = task.contacts.filter { !$0.email.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !withAddresses.isEmpty else { return nil }
        if !waiting.isEmpty,
           let named = withAddresses.first(where: {
               $0.name.lowercased().contains(waiting) || waiting.contains($0.name.lowercased())
                   || $0.email.lowercased().hasPrefix(waiting)
           }) {
            return named
        }
        // One contact and a strip waiting on somebody: it's them.
        return withAddresses.count == 1 ? withAddresses[0] : nil
    }

    /// How long this has been waiting, in whole days.
    static func daysWaiting(_ task: TaskItem, now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let since = task.waitingOnSince else { return nil }
        return calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: since), to: calendar.startOfDay(for: now)
        ).day
    }

    /// The message-id of the email this strip came from, where it has one, so a chase arrives
    /// under the conversation it belongs to rather than as a new one.
    static func originalMessageID(of task: TaskItem) -> String? {
        for link in task.links where EmailLink.isMessage(link.url) {
            guard let scheme = link.url.range(of: "://") else { continue }
            let rest = String(link.url[scheme.upperBound...])
            let decoded = rest.removingPercentEncoding ?? rest
            let id = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            if !id.isEmpty { return id }
        }
        return nil
    }

    /// The chase itself: short, polite, and specific about what and since when — the three things
    /// that make a reminder answerable rather than annoying.
    static func draft(
        for task: TaskItem,
        from account: IMAPAccount,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> MailDraft {
        let contact = recipient(of: task)
        let name = firstName(of: contact?.name ?? task.waitingOnName)
        let days = daysWaiting(task, now: now, calendar: calendar)

        var lines = [name.isEmpty ? "Hello," : "Hello \(name),"]
        lines.append("")
        lines.append(body(title: task.title, days: days, since: task.waitingOnSince, calendar: calendar))
        lines.append("")
        lines.append("Thank you,")
        if let sender = account.senderName, !sender.isEmpty { lines.append(sender) }

        return MailDraft(
            from: account.email,
            fromName: account.senderName ?? "",
            to: contact?.email ?? "",
            subject: subject(for: task),
            body: lines.joined(separator: "\n"),
            signature: account.signature,
            inReplyTo: originalMessageID(of: task)
        )
    }

    static func subject(for task: TaskItem) -> String {
        let title = task.title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? "Following up" : "Following up: \(title)"
    }

    static func body(title: String, days: Int?, since: Date?, calendar: Calendar = .current) -> String {
        let what = title.trimmingCharacters(in: .whitespaces)
        let subject = what.isEmpty ? "the item below" : "\u{201C}\(what)\u{201D}"
        guard let days, days > 0 else {
            return "I'm following up on \(subject). Could you let me know where it stands?"
        }
        let when = since.map { " since \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        let waited = days == 1 ? "a day" : "\(days) days"
        return "I'm following up on \(subject) — it's been with you\(when), \(waited) now. "
            + "Could you let me know where it stands?"
    }

    /// "Bassam" out of "Bassam Alfeeli": a chase is a note between two people, not a letter.
    static func firstName(of name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? ""
    }

    /// What the strip's log says, and what pushes the next nudge out.
    static func logLine(to name: String) -> String {
        name.isEmpty ? "Chased by email" : "Chased \(name) by email"
    }
}
