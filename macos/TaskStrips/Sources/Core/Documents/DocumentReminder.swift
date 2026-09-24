import Foundation

/// Turning a date read off a document into a reminder somebody will actually get.
///
/// A due date sits on the strip; a reminder is its own row in the reminders list, with its own
/// time and its own alarm. A document that expires in eighteen months is the second kind — there
/// is no work to do on it today, and a strip would only clutter the board until the month it
/// matters.
enum DocumentReminder {
    /// What the reminder is called: what the document called it, then the document's own name.
    ///
    /// "Expires — passport.pdf" rather than the line it was found on, which can be half a page
    /// wide and reads as noise in a list.
    static func title(for found: FoundDate, document: String, strip: String = "") -> String {
        let what = found.kind == .unknown ? "Date" : found.kind.label
        let subject = strip.trimmingCharacters(in: .whitespaces).isEmpty
            ? document
            : strip.trimmingCharacters(in: .whitespaces)
        return subject.isEmpty ? what : "\(what) — \(subject)"
    }

    /// The line it was read from, kept as the details so the reminder can be checked against the
    /// document later without opening it.
    static func details(for found: FoundDate, document: String) -> String {
        let source = document.isEmpty ? "" : "\nRead from \(document)"
        return found.context + source
    }

    /// Nine in the morning on the day, rather than the stroke of midnight a bare date means.
    ///
    /// A date on a document has no time in it; midnight is a reminder that arrives while
    /// somebody's asleep and is gone by breakfast.
    static let hour = 9

    static func triggerAt(_ date: Date, calendar: Calendar = .current) -> Date {
        // A date that already carries a time of day keeps it: "3pm on the 14th" means 3pm.
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        if (parts.hour ?? 0) != 0 || (parts.minute ?? 0) != 0 { return date }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
    }

    /// How far ahead to warn, where warning ahead is the point.
    ///
    /// A deadline or an expiry is no use on the morning it lands — a passport that expires today
    /// is already a problem. A week's notice is what makes it actionable; an appointment is about
    /// the day itself, so it comes on the day.
    static func leadMinutes(for kind: DocumentDates.Meaning) -> Int? {
        switch kind {
        case .deadline, .expiry: return 7 * 24 * 60
        case .appointment, .issued, .unknown: return nil
        }
    }
}
