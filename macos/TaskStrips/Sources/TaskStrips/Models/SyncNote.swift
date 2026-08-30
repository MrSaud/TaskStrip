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
    var title: String
    var text: String
    var updatedAt: Date
    /// Kept as a tombstone until a sync has carried the delete, then it is nothing but a row that
    /// says "this is gone" — which is exactly what the other device needs to hear.
    var isDeleted: Bool

    init(
        syncID: String = UUID().uuidString,
        title: String = "",
        text: String = "",
        updatedAt: Date = .now,
        isDeleted: Bool = false
    ) {
        self.syncID = syncID
        self.title = title
        self.text = text
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    var record: SyncNoteRecord {
        SyncNoteRecord(id: syncID, title: title, text: text, updatedAt: updatedAt, isDeleted: isDeleted)
    }

    func apply(_ record: SyncNoteRecord) {
        title = record.title
        text = record.text
        updatedAt = record.updatedAt
        isDeleted = record.isDeleted
    }
}
