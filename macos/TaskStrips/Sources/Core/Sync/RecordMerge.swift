import CloudKit

/// Field-by-field merging, for when a save meets a server record another device changed first.
///
/// Three copies are compared: the one this device last received (the base), what this device
/// wants now (local), and what the server has now. A field this device changed since the base
/// takes its local value; every other field takes the server's. So two devices editing different
/// fields of one strip both keep their edit, and only a field both changed is decided — in favour
/// of whoever saves last, which is the one that saw the other's change arrive.
enum RecordMerge {
    /// The server's record, with this device's changes laid over it. Keeps the server's change
    /// tag, so saving it goes through.
    static func merge(base: CKRecord?, local: CKRecord, server: CKRecord) -> CKRecord {
        for key in Set(local.allKeys()).union(base?.allKeys() ?? []) {
            let mine = local[key]
            // Files don't change once added, and an asset's local path says nothing about its
            // bytes: keep whatever the server holds unless this device is adding one.
            if mine is CKAsset, server[key] != nil, base?[key] != nil { continue }
            if !same(mine, base?[key]) { server[key] = mine }
        }
        let localSecret = local.encryptedValues
        let baseSecret = base?.encryptedValues
        for key in Set(localSecret.allKeys()).union(baseSecret?.allKeys() ?? []) {
            let mine = localSecret[key]
            if !same(mine, baseSecret?[key]) { server.encryptedValues[key] = mine }
        }
        return server
    }

    /// Whether two field values are the same value. Nil and missing are the same.
    static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a as NSObject, b as NSObject): return a.isEqual(b)
        default: return false
        }
    }

    /// The fields in which `local` differs from `base` — plain and encrypted, file fields aside.
    /// Empty means there's nothing to send.
    static func changedKeys(local: CKRecord, base: CKRecord?) -> Set<String> {
        var changed = Set<String>()
        for key in Set(local.allKeys()).union(base?.allKeys() ?? []) {
            if local[key] is CKAsset, base?[key] != nil { continue }
            if !same(local[key], base?[key]) { changed.insert(key) }
        }
        let secret = local.encryptedValues
        for key in Set(secret.allKeys()).union(base?.encryptedValues.allKeys() ?? []) {
            if !same(secret[key], base?.encryptedValues[key]) { changed.insert(key) }
        }
        return changed
    }
}

/// The brake on deleting from iCloud.
///
/// A device works out what to delete by comparing what it has with what it last saw in iCloud.
/// If its store is emptied — a restore that replaces the board, a wipe, a bug — that comparison
/// says "delete everything", and every other device would follow. So a large batch of deletions
/// is held until the person says yes, and small everyday ones go straight through.
enum DeletionGuard {
    static func needsConfirmation(deleting: Int, ofSynced synced: Int) -> Bool {
        guard deleting > 0 else { return false }
        if deleting > 20 { return true }
        return deleting >= 5 && deleting * 3 >= synced
    }
}
