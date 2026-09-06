import Foundation
import SwiftData

/// Deleting, for anything that syncs.
///
/// A removed row is indistinguishable from one the other device has never heard of, so the next
/// sync would bring every deleted strip back from the dead. The row has to outlive the thing long
/// enough to say it is gone — that is what `isDeleted` is for, and every query a person sees
/// through has to filter these out.
protocol Deletable: AnyObject {
    var isTombstoned: Bool { get set }
    var updatedAt: Date? { get set }
}

extension TaskItem: Deletable {}
extension Reminder: Deletable {}
extension Credential: Deletable {}
extension StorageItem: Deletable {}

extension ModelContext {
    /// A tombstone, not a removal.
    ///
    /// Named apart from `delete(_:)` rather than shadowing it, so the hard delete is still
    /// reachable and obviously different at the call site — the sync's own tombstone sweep and a
    /// restore, which rebuilds the store from nothing, both genuinely want rows gone.
    func tombstone(_ model: some Deletable) {
        model.isTombstoned = true
        model.updatedAt = .now
    }
}
