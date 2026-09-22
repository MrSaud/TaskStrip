import Foundation

/// One synced text, as it travels.
///
/// `id` is a UUID string minted once and never regenerated — it is the only thing that lets two
/// devices agree they are looking at the same note rather than at two notes that happen to say the
/// same words. A row's local database key is never it: Android's is an autoincrementing Int and
/// the Mac's is a SwiftData object, and neither means anything on the other machine.
struct SyncNoteRecord: Identifiable, Equatable {
    var id: String
    /// The whole note. A synced note is one text with no title of its own.
    var text: String
    var updatedAt: Date
    /// A deleted note stays in the document as a tombstone. Dropping the row instead would make a
    /// delete indistinguishable from "the other device hasn't heard of this yet", and the note
    /// would come back from the dead on the next sync.
    var isDeleted: Bool

    /// What to call it in a list: its first non-blank line, the same rule the quick-notes
    /// scratchpad uses to name a strip it promotes.
    var displayTitle: String {
        let firstLine = text.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let line = firstLine.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        if line.isEmpty { return "Untitled" }
        return line.count <= 80 ? line : String(line.prefix(80))
    }
}

/// The document both apps read and write: one JSON file in the Drive folder they already share.
///
/// Deliberately one file rather than one per note. Two devices editing different notes at the same
/// time is the common case and a per-note file would handle it slightly better; but a single file
/// is one download, one upload and one atomic replacement, and the merge below already keeps both
/// devices' edits to *different* notes. What one file costs is a same-second edit of the *same*
/// note from both devices, which loses one side — see `winner`.
enum SyncNoteDocument {
    static let fileName = "sync_notes.json"
    static let mimeType = "application/json"

    /// 2 dropped the per-note `title` in favour of one text whose first line names it.
    ///
    /// Nothing reads this number to decide how to parse — a v1 document parses correctly under
    /// these rules, because `notes(from:)` still folds a title it finds into the text, and a v2
    /// document parses correctly under v1's rules too, because a missing title simply falls back
    /// to the first line there as well. It is written so the file says which app wrote it.
    static let version = 2

    /// A note written before the title was dropped, as one text.
    ///
    /// The title becomes the first line, which is the position the name is now read from — so a
    /// note called "Groceries" is still called "Groceries" afterwards. Must stay byte-identical to
    /// `foldLegacyTitle` in SyncNoteDocument.kt: the two devices fold independently and have to
    /// land on the same string, or the merge sees two different texts and picks a winner forever.
    static func foldLegacyTitle(_ title: String, _ text: String) -> String {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        return title + "\n" + text
    }

    // MARK: - Reading and writing

    /// Milliseconds since the epoch, because that is what Android writes everywhere else in this
    /// app and the two have to read each other's numbers without a second thought.
    static func data(for notes: [SyncNoteRecord]) throws -> Data {
        let objects: [[String: Any]] = sorted(notes).map { note in
            [
                "id": note.id,
                "text": note.text,
                "updatedAt": Int(note.updatedAt.timeIntervalSince1970 * 1000),
                "deleted": note.isDeleted,
            ]
        }
        return try JSONSerialization.data(
            withJSONObject: ["version": version, "notes": objects],
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    /// Anything unreadable is no notes rather than an error. A corrupt or half-written document in
    /// Drive must not be able to wipe what's on this machine — the merge treats "no remote" as
    /// "nothing to add", and the next upload writes a good document over it.
    static func notes(from data: Data) -> [SyncNoteRecord] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = root["notes"] as? [[String: Any]]
        else { return [] }

        return array.compactMap { object in
            guard let id = object["id"] as? String, !id.isEmpty else { return nil }
            let millis = (object["updatedAt"] as? NSNumber)?.doubleValue ?? 0
            return SyncNoteRecord(
                id: id,
                text: foldLegacyTitle(
                    object["title"] as? String ?? "",
                    object["text"] as? String ?? ""
                ),
                updatedAt: Date(timeIntervalSince1970: millis / 1000),
                isDeleted: object["deleted"] as? Bool ?? false
            )
        }
    }

    // MARK: - Merging

    /// Both sides' notes, one winner per id.
    ///
    /// Order-independent on purpose: `merge(local, remote)` and `merge(remote, local)` produce the
    /// same thing, so the phone and the Mac reach the same answer without having to agree on who
    /// went first. That is what `winner`'s tie-breaks are for.
    static func merge(local: [SyncNoteRecord], remote: [SyncNoteRecord]) -> [SyncNoteRecord] {
        var byID: [String: SyncNoteRecord] = [:]
        for note in local + remote {
            byID[note.id] = byID[note.id].map { winner($0, note) } ?? note
        }
        return sorted(Array(byID.values))
    }

    /// Newer wins. Then a delete wins over a live note, because a delete is a decision and a stale
    /// edit is not. Then the greater text, purely so that two devices holding genuinely different
    /// text stamped at the same millisecond still pick the *same* side and stop disagreeing.
    static func winner(_ a: SyncNoteRecord, _ b: SyncNoteRecord) -> SyncNoteRecord {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt ? a : b }
        if a.isDeleted != b.isDeleted { return a.isDeleted ? a : b }
        if a.text != b.text { return isGreater(a.text, b.text) ? a : b }
        return a
    }

    /// Compares UTF-8 bytes, not Swift strings.
    ///
    /// `>` on a Swift String orders grapheme clusters under canonical equivalence; Kotlin's orders
    /// UTF-16 code units. For ASCII they agree and for Arabic they need not — and a tie-break the
    /// two platforms disagree about is worse than no tie-break at all, because the devices would
    /// hand each other opposite answers forever. Bytes are the one ordering both can compute the
    /// same way without either having to imitate the other's string semantics.
    static func isGreater(_ a: String, _ b: String) -> Bool {
        Array(b.utf8).lexicographicallyPrecedes(Array(a.utf8))
    }

    /// Newest first, and by id where the times match, so the file's bytes don't churn between
    /// syncs that changed nothing.
    static func sorted(_ notes: [SyncNoteRecord]) -> [SyncNoteRecord] {
        notes.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
        }
    }

    /// What a person should see: tombstones are bookkeeping, not notes.
    static func visible(_ notes: [SyncNoteRecord]) -> [SyncNoteRecord] {
        sorted(notes.filter { !$0.isDeleted })
    }
}
