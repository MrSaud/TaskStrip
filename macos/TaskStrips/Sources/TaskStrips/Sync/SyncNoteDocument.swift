import Foundation

/// One synced text, as it travels.
///
/// `id` is a UUID string minted once and never regenerated — it is the only thing that lets two
/// devices agree they are looking at the same note rather than at two notes that happen to say the
/// same words. A row's local database key is never it: Android's is an autoincrementing Int and
/// the Mac's is a SwiftData object, and neither means anything on the other machine.
struct SyncNoteRecord: Identifiable, Equatable {
    var id: String
    var title: String
    var text: String
    var updatedAt: Date
    /// A deleted note stays in the document as a tombstone. Dropping the row instead would make a
    /// delete indistinguishable from "the other device hasn't heard of this yet", and the note
    /// would come back from the dead on the next sync.
    var isDeleted: Bool

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        // Falls back to the first non-blank line, the same rule the quick-notes scratchpad uses
        // to name a strip it promotes.
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
    static let version = 1

    // MARK: - Reading and writing

    /// Milliseconds since the epoch, because that is what Android writes everywhere else in this
    /// app and the two have to read each other's numbers without a second thought.
    static func data(for notes: [SyncNoteRecord]) throws -> Data {
        let objects: [[String: Any]] = sorted(notes).map { note in
            [
                "id": note.id,
                "title": note.title,
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
                title: object["title"] as? String ?? "",
                text: object["text"] as? String ?? "",
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
        if a.text != b.text { return a.text > b.text ? a : b }
        return a.title >= b.title ? a : b
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
