import Foundation

/// A strip and email, in both directions: the email a strip came from, and the email a strip is
/// sent as.
///
/// The text is built here rather than where it's sent, so the Mac and the phone send the same
/// message and the wording can be checked without a mail client in the room.
enum StripMail {
    // MARK: - The email a strip came from

    /// Schemes that mean "a message in a mail app" rather than a page on the web. `message:` is
    /// what Mail hands over when a message is dragged out of it; the others are what other mail
    /// apps use for the same thing.
    static let messageSchemes: Set<String> = ["message", "x-msg", "emailmessage", "mailto"]

    static func isMessageLink(_ url: String) -> Bool {
        guard let scheme = URL(string: url.trimmingCharacters(in: .whitespaces))?.scheme?.lowercased() else {
            return false
        }
        return messageSchemes.contains(scheme)
    }

    /// What a linked message is called on the strip when it carries no label of its own: a
    /// `message:` URL is a long opaque id, and showing that helps nobody.
    static func label(for url: String) -> String {
        guard isMessageLink(url) else { return url }
        if let address = URL(string: url)?.scheme?.lowercased(), address == "mailto" {
            let to = url.dropFirst("mailto:".count).prefix { $0 != "?" }
            return to.isEmpty ? "Email" : "Email \(to)"
        }
        return "Email message"
    }

    // MARK: - The email a strip is sent as

    static func subject(for task: TaskItem) -> String {
        task.title.isEmpty ? "Task Strips" : task.title
    }

    /// The strip as a person would write it out: what it is, when it's due, how far along, and
    /// then whatever was written on it. Anything empty is left out rather than shown blank.
    static func body(for task: TaskItem, now: Date = .now, locale: Locale = .current) -> String {
        var lines: [String] = []

        var facts: [String] = ["Priority: \(task.priority.label.capitalized)"]
        if let due = task.dueAt {
            facts.append("Due: \(due.formatted(date: .abbreviated, time: .shortened))")
        }
        if task.progress > 0 { facts.append("Progress: \(task.progress)%") }
        if task.isDone { facts.append("Done") }
        if !task.tags.isEmpty { facts.append("Tags: \(task.tags.joined(separator: ", "))") }
        lines.append(facts.joined(separator: "  ·  "))

        let notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines.append("")
            lines.append(notes)
        }

        let links = task.links.filter { !$0.url.trimmingCharacters(in: .whitespaces).isEmpty }
        if !links.isEmpty {
            lines.append("")
            lines.append("Links:")
            // A message: link means nothing to anyone else's mail app, so it stays behind.
            for link in links where !isMessageLink(link.url) {
                lines.append(link.label.isEmpty ? link.url : "\(link.label) — \(link.url)")
            }
        }

        if !task.contacts.isEmpty {
            lines.append("")
            lines.append("People: " + task.contacts.map(\.name).joined(separator: ", "))
        }

        lines.append("")
        lines.append("— Sent from Task Strips")
        return lines.joined(separator: "\n")
    }

    /// A mailto: URL, for when there's no mail client to talk to properly. Everything is escaped,
    /// because a subject with an ampersand in it would otherwise lose half the body.
    static func mailtoURL(to recipient: String = "", subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        // URLComponents leaves these two legal-but-unwelcome in a mailto body; Mail reads the
        // escaped form correctly and the raw form as the start of a new field.
        let query = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "&amp;", with: "%26")
        components.percentEncodedQuery = query
        return components.url
    }

    /// Which of a strip's files fit in an email, in order, and which don't.
    ///
    /// Mail servers refuse a message over about 25 MB, and a refused message is worse than a
    /// short one: it fails after it looks sent. So the big ones stay behind and the body says so.
    static let attachmentLimit = 20 * 1024 * 1024

    static func attachmentsThatFit(_ sizes: [Int], limit: Int = attachmentLimit) -> (sent: [Int], left: [Int]) {
        var total = 0
        var sent: [Int] = []
        var left: [Int] = []
        for (index, size) in sizes.enumerated() {
            if size <= 0 || total + size > limit {
                left.append(index)
            } else {
                total += size
                sent.append(index)
            }
        }
        return (sent, left)
    }

    static func note(forFilesLeftBehind names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let list = names.joined(separator: ", ")
        return names.count == 1
            ? "\n(\(list) was too large to attach.)"
            : "\n(\(list) were too large to attach.)"
    }
}
