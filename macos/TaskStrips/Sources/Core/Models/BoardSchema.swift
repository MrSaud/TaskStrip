import Foundation
import SwiftData

/// Every kind of thing the board stores, in one list. The Mac and the iPhone/iPad app both open
/// their store with it, so neither can quietly leave a model out and end up with a store the
/// other side can't read.
enum BoardSchema {
    static let models: [any PersistentModel.Type] = [
        TaskItem.self, Note.self, StorageItem.self, Reminder.self, Credential.self, SyncNote.self,
    ]

    /// The on-disk store. `cloudKitDatabase: .none` is not optional: once the app carries the
    /// iCloud entitlement, SwiftData's default is to mirror the store through CloudKit by
    /// itself — and it refuses to open at all, because these models have unique ids and
    /// required fields its mirroring can't handle. Sync is ours, through CKSyncEngine, so the
    /// automatic mirroring stays off everywhere.
    static func configuration(url: URL) -> ModelConfiguration {
        ModelConfiguration(url: url, cloudKitDatabase: .none)
    }
}
