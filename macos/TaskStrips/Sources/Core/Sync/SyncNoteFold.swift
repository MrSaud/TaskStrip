import Foundation
import SwiftData

/// Sync Notes are folded into Notes (decided 2026-09-22): the iPhone and iPad have no Sync Notes
/// screen, and once the whole board syncs they're one more copy of the same idea. The Mac's
/// Sync Note text becomes an ordinary quick note, once, when sync is first turned on — after
/// the Android import, which doesn't carry it.
enum SyncNoteFold {
    private static let doneKey = "syncNotes.foldedIntoNotes"

    @discardableResult
    static func run(in context: ModelContext, defaults: UserDefaults = .standard) -> Int {
        guard !defaults.bool(forKey: doneKey) else { return 0 }
        let syncNotes = ((try? context.fetch(FetchDescriptor<SyncNote>())) ?? []).filter { !$0.isTombstoned }
        let existing = Set(((try? context.fetch(FetchDescriptor<Note>())) ?? []).map(\.text))
        var added = 0
        for syncNote in syncNotes {
            let text = syncNote.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !existing.contains(text) else { continue }
            context.insert(Note(text: text, createdAt: syncNote.updatedAt))
            added += 1
        }
        try? context.save()
        defaults.set(true, forKey: doneKey)
        return added
    }
}
