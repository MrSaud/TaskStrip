import Foundation

/// A spoken quick-add, pulled apart into the fields a strip has.
///
/// Mirrors VoiceDraft in VoiceCommandParser.kt, minus its contactEmail/contactPhone: those exist
/// only for a draft that arrived from a shared vCard, and the Mac has no share target to receive
/// one.
struct VoiceDraft: Equatable {
    var title: String = ""
    var notes: String = ""
    var priority: Priority?
}

/// Best-effort pattern matching for spoken quick-add commands, ported from
/// VoiceCommandParser.kt:
///
///     "create a strip for project a, description is call the vendor about pricing"
///     -> title "Project a", notes "call the vendor about pricing"
///
/// Deliberately simple matching rather than anything cleverer, and for the reason Android gives:
/// the result is always shown for review before it's saved, because speech recognition and this
/// kind of matching are both fallible. A parser that guessed harder would be wrong more
/// confidently.
enum VoiceCommandParser {
    /// Longest first, so "create a strip for" wins over "create a strip".
    private static let leadingPhrases = [
        "create a strip for", "create a strip", "create strip for", "create strip",
        "new strip for", "new strip", "add a strip for", "add a strip", "add strip for", "add strip",
        "create a task for", "create a task", "create task for", "create task",
        "new task for", "new task", "add a task for", "add a task", "add task for", "add task",
        "file a strip for", "file a strip",
    ].sorted { $0.count > $1.count }

    private static let descriptionKeywords = [
        "the description is", "description is", "notes are", "notes is",
        "with description", "description", "notes",
    ].sorted { $0.count > $1.count }

    private static let priorityWords: [(word: String, priority: Priority)] = [
        ("urgent", .urgent),
        ("high priority", .high),
        ("low priority", .low),
        ("normal priority", .normal),
    ]

    static func parse(_ raw: String) -> VoiceDraft {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let lead = leadingPhrases.first(where: { text.lowercased().hasPrefix($0) }) {
            text = String(text.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
        }

        var priority: Priority?
        if let hit = priorityHit(in: text) {
            priority = hit.priority
            // Lifting "urgent" out of "renew the visa, urgent, notes …" leaves ", ," behind.
            // Android collapses only a literal ",,", which never matches once there's a space
            // between them, so its titles keep a dangling comma; this collapses the spaced form
            // too. A deliberate difference, and the only one in this port.
            text = (String(text[text.startIndex..<hit.range.lowerBound])
                    + String(text[hit.range.upperBound...]))
                .replacingOccurrences(of: ",\\s*,", with: ",", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }

        let title: String
        let notes: String
        if let hit = descriptionHit(in: text) {
            title = trimmed(String(text[text.startIndex..<hit.lowerBound]))
            notes = String(text[hit.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else if let comma = text.firstIndex(of: ",") {
            // No keyword, so the first comma is the seam: "renew the passport, before the trip".
            title = trimmed(String(text[text.startIndex..<comma]))
            notes = String(text[text.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        } else {
            title = trimmed(text)
            notes = ""
        }

        // Everything stripped away and nothing left means the matching went wrong, not that the
        // user said nothing — better to file what they actually said than an empty strip.
        let finalTitle = title.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : title
        return VoiceDraft(title: capitalizingFirstLetter(finalTitle), notes: notes, priority: priority)
    }

    /// Matched on word boundaries, so "urgently" isn't a priority and neither is a title that
    /// merely contains the letters.
    private static func priorityHit(in text: String) -> (range: Range<String.Index>, priority: Priority)? {
        priorityWords
            .compactMap { word, priority -> (Range<String.Index>, Priority)? in
                guard let range = wordRange(of: word, in: text) else { return nil }
                return (range, priority)
            }
            // Longest match first, so "high priority" beats a bare "priority" appearing later.
            .max { lhs, rhs in
                text.distance(from: lhs.0.lowerBound, to: lhs.0.upperBound)
                    < text.distance(from: rhs.0.lowerBound, to: rhs.0.upperBound)
            }
            .map { (range: $0.0, priority: $0.1) }
    }

    private static func descriptionHit(in text: String) -> Range<String.Index>? {
        // The earliest keyword wins, since the first one said is the seam between the two halves.
        descriptionKeywords
            .compactMap { wordRange(of: $0, in: text) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    private static func wordRange(of word: String, in text: String) -> Range<String.Index>? {
        text.range(
            of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// Whitespace and commas together, in whatever order they were left in — one pass of each
    /// isn't enough for "renew the visa, ,".
    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
    }

    private static func capitalizingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
