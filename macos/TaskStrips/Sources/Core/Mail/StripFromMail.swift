import Foundation

/// Making a strip out of a message.
///
/// Most work arrives as mail, and the step that was still done by hand was the transcription:
/// read the message, type a title, copy the date out of it, save the attachment somewhere, and
/// remember which email it was. All of that is in the message already.
enum StripFromMail {
    /// Everything a strip needs, worked out before anything is created — so what it will do can
    /// be checked without a database.
    struct Plan: Equatable {
        var title: String
        var notes: String
        var link: String?
        var linkLabel: String
        var contactName: String
        var contactEmail: String
        /// Taken from the message when the message clearly names one.
        var dueAt: Date?
        /// What the date was called in the message — "Deadline", "Expires" — for the log line.
        var dueKind: DocumentDates.Meaning?
    }

    /// How much of a message goes into the notes. Enough to know what it was about without
    /// pasting a newsletter onto the board.
    static let noteLimit = 1_500

    static func plan(for message: MailMessage, body: MailBody?, now: Date = .now) -> Plan {
        let subject = message.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let sender = message.senderName.trimmingCharacters(in: .whitespaces)
        let found = dueDate(in: body?.text ?? "", now: now)

        return Plan(
            // A strip with no title is a strip nobody can find; a message with no subject still
            // has somebody who sent it.
            title: subject.isEmpty ? (sender.isEmpty ? "Email" : "Email from \(sender)") : subject,
            notes: notes(from: message, body: body),
            link: message.link,
            linkLabel: subject,
            contactName: sender == message.senderAddress ? "" : sender,
            contactEmail: message.senderAddress ?? "",
            dueAt: found?.date,
            dueKind: found?.kind
        )
    }

    /// The message itself, under a line saying where it came from — so a strip read a month later
    /// still says who asked for it and when.
    static func notes(from message: MailMessage, body: MailBody?) -> String {
        let header = "From \(message.sender) · \(message.receivedAt.formatted(date: .abbreviated, time: .shortened))"
        let text = (body?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return header }
        let shown = text.count > noteLimit ? String(text.prefix(noteLimit)) + "…" : text
        return header + "\n\n" + shown
    }

    /// The date the message is actually asking for, if it names one.
    ///
    /// Only a deadline or an expiry, and only one still ahead: an invoice's own issue date is not
    /// a due date, and last month's deadline on a strip made today is worse than no date at all.
    static func dueDate(in text: String, now: Date = .now) -> FoundDate? {
        let found = DocumentDates.find(in: text, now: now).filter { $0.date > now }
        if let named = found.first(where: {
            $0.kind == .deadline || $0.kind == .expiry || $0.kind == .appointment
        }) {
            return named
        }
        // Nothing labelled, but a message with exactly one date ahead of it is usually about that
        // date — "the meeting is on the 14th". Two or more and it's anybody's guess, so nothing
        // is guessed.
        let unlabelled = found.filter { $0.kind == .unknown }
        return unlabelled.count == 1 ? unlabelled.first : nil
    }

    /// What the strip's log says about where it came from.
    static func logLine(for plan: Plan) -> String {
        guard let kind = plan.dueKind, plan.dueAt != nil else { return "Filed from an email" }
        guard kind != .unknown else { return "Filed from an email · due date read from it (the only date in it)" }
        return "Filed from an email · due date read from it (\(kind.label.lowercased()))"
    }
}
