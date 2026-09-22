import Foundation

/// Turning a note into work.
///
/// Mirrors the two actions in NotesScreen.kt. Pure, so the rules — which line becomes the title,
/// what counts as a line worth splitting on, what a checkbox prefix looks like — are testable
/// without a view.
enum NotePromotion {
    /// Android truncates titles here, and a strip title that runs to a paragraph is unreadable on
    /// the board anyway.
    static let titleLimit = 80

    /// One strip carrying the whole note: the first line becomes the title, the full text becomes
    /// the notes field, so nothing is lost in the promotion.
    ///
    /// Android takes `lineSequence().firstOrNull()`, which yields an empty title when the note
    /// starts with a blank line. Taking the first *non-blank* line instead is the same intent
    /// without the degenerate case — and a strip with no title can't be saved through the editor,
    /// so it isn't a state worth creating here either.
    static func strip(from note: Note, orderIndex: Int) -> TaskItem {
        let title = note.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            ?? note.text

        let task = TaskItem(title: String(title.prefix(titleLimit)), orderIndex: orderIndex)
        task.notes = note.text
        return task
    }

    /// The lines a note would split into: non-blank, trimmed, in order.
    ///
    /// Splitting is only worth offering when there's more than one, which is what Android gates
    /// the button on.
    static func splitLines(of text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// A checklist pasted into a note becomes one strip per line.
    ///
    /// The checkbox prefixes come off first — a title reading "[ ] call the consulate" carries
    /// its own leftover formatting, and the strip already has a done state of its own.
    static func strips(splitting note: Note, startingAt orderIndex: Int) -> [TaskItem] {
        splitLines(of: note.text).enumerated().map { offset, line in
            let cleaned = stripCheckbox(from: line)
            let title = cleaned.isEmpty ? line : cleaned
            return TaskItem(title: String(title.prefix(titleLimit)), orderIndex: orderIndex + offset)
        }
    }

    static func stripCheckbox(from line: String) -> String {
        for marker in ["[ ]", "[x]", "[X]", "[✓]"] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }
}
