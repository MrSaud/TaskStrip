import Foundation
import SwiftData

/// A text that exists on both machines.
///
/// Separate from `Note`, the local scratchpad, and deliberately so: a quick note is a thought you
/// jot and promote or throw away on the machine you jotted it on, while this is one text with two
/// windows onto it. Merging the two would mean either syncing every stray thought or making the
/// scratchpad think about conflicts.
@Model
final class SyncNote {
    /// The shared identity — see SyncNoteRecord. Not the SwiftData object id, which means nothing
    /// on a phone.
    @Attribute(.unique) var syncID: String
    /// The whole note. There is no separate title: a synced note is one text, and what a list
    /// needs to call it is its first line — see `SyncNoteRecord.displayTitle`.
    var text: String
    var updatedAt: Date
    /// Tombstoned: kept until a sync has carried the delete, then nothing but a row that says
    /// "this is gone" — which is exactly what the other device needs to hear.
    ///
    /// Renamed off `isDeleted`, which SwiftData's own PersistentModel already defines as "removed
    /// from the context". A stored property of that name shadows it and the two disagree, so the
    /// list's filter was reading SwiftData's answer — always false — rather than this one.
    /// Defaulted, unlike the property it replaced. Renaming makes this a *new* attribute as far
    /// as the store is concerned, and a new non-optional one with no default is a store that
    /// refuses to migrate — the app then fails to launch rather than misbehaving quietly.
    var isTombstoned: Bool = false

    init(
        syncID: String = UUID().uuidString,
        text: String = "",
        updatedAt: Date = .now,
        isTombstoned: Bool = false
    ) {
        self.syncID = syncID
        self.text = text
        self.updatedAt = updatedAt
        self.isTombstoned = isTombstoned
    }

    var record: SyncNoteRecord {
        SyncNoteRecord(id: syncID, text: text, updatedAt: updatedAt, isDeleted: isTombstoned)
    }

    func apply(_ record: SyncNoteRecord) {
        text = record.text
        updatedAt = record.updatedAt
        isTombstoned = record.isDeleted
    }
}
