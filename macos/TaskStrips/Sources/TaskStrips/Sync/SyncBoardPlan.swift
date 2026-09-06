import Foundation

/// What a sync should do to this machine, worked out before anything is written.
///
/// Mirrors SyncBoardPlan.kt. Separated from the writing on purpose: deciding is identical on both
/// platforms and is the part that can quietly lose a strip; writing is SwiftData here and Room
/// there and can only be checked by running it. Keeping them apart means the dangerous half is the
/// half under test.
struct BoardPlan<T>: Equatable where T: Equatable {
    /// Rows the merge knows about and this machine doesn't.
    var insert: [T] = []
    /// Rows both sides hold where the merge picked something this machine isn't already showing.
    var update: [T] = []
    /// Shared ids whose rows are tombstoned and should go from this machine.
    var delete: [String] = []

    var isEmpty: Bool { insert.isEmpty && update.isEmpty && delete.isEmpty }
}

/// How this machine should treat what it finds in the shared folder.
enum SyncStance {
    /// The usual: reconcile both sides record by record.
    case merge

    /// The other device's board is taken wholesale, replacing this one.
    ///
    /// Only for a first sync between two devices whose boards already overlap but were never given
    /// matching ids — a merge there would union them and duplicate every row that exists on both.
    /// The user names which device wins; this is what the loser does once.
    case adopt
}

/// The decisions a sync makes before it touches the store.
enum SyncBoardPlan {

    /// Whether to reconcile or to take the other side wholesale.
    ///
    /// Adopting is guarded twice over: only on a machine that has never synced, and only when the
    /// folder actually holds a board. Without the second guard, a first sync against an empty or
    /// unreachable folder would read "nothing" as the truth and wipe the board it was supposed to
    /// be protecting — the single worst thing this feature could do.
    static func stance(
        hasSyncedBefore: Bool,
        remoteIsEmpty: Bool,
        adoptsOnFirstSync: Bool
    ) -> SyncStance {
        !hasSyncedBefore && adoptsOnFirstSync && !remoteIsEmpty ? .adopt : .merge
    }

    /// What to insert, update and delete, given what this machine holds and what the merge decided.
    ///
    /// A row identical on both sides appears in none of the three lists — a sync that changed
    /// nothing must write nothing, or every sync churns the store and every view watching it.
    static func plan<T: Equatable>(
        localByID: [String: T],
        merged: [T],
        id: (T) -> String,
        isDeleted: (T) -> Bool
    ) -> BoardPlan<T> {
        var plan = BoardPlan<T>()
        for record in merged {
            let key = id(record)
            let local = localByID[key]
            if isDeleted(record) {
                // A tombstone for something this machine never had is not a deletion, it is
                // nothing at all — inserting it just to delete it would be work for no one.
                if local != nil { plan.delete.append(key) }
            } else if local == nil {
                plan.insert.append(record)
            } else if local != record {
                plan.update.append(record)
            }
        }
        return plan
    }

    /// Strips whose blocker no longer exists, with the link cut.
    ///
    /// A blocker can be deleted on the other device between one sync and the next. Left alone, the
    /// strip it blocked would stay blocked forever by something nobody can see or finish — the
    /// board would refuse to let it be marked done and never say why.
    static func clearDanglingBlockers(_ tasks: [SyncTaskRecord]) -> [SyncTaskRecord] {
        let alive = Set(tasks.filter { !$0.isDeleted }.map(\.id))
        return tasks.map { task in
            guard let blocker = task.blockedBySyncID, !alive.contains(blocker) else { return task }
            var cleared = task
            cleared.blockedBySyncID = nil
            return cleared
        }
    }

    /// Strips whose linked sketch no longer exists, with the link cut — the same problem as a
    /// dangling blocker, and left alone it opens an empty canvas or nothing at all.
    static func clearDanglingSketchLinks(
        _ tasks: [SyncTaskRecord],
        sketches: [SyncSketchRecord]
    ) -> [SyncTaskRecord] {
        let alive = Set(sketches.filter { !$0.isDeleted }.map(\.id))
        return tasks.map { task in
            guard let link = task.linkedSketchSyncID, !alive.contains(link) else { return task }
            var cleared = task
            cleared.linkedSketchSyncID = nil
            return cleared
        }
    }

    /// A strip cannot block itself.
    ///
    /// Not reachable through the UI, but a merge can build it: two devices each pointing a pair of
    /// strips at the other, and the winners taken separately, is enough.
    static func clearSelfBlockers(_ tasks: [SyncTaskRecord]) -> [SyncTaskRecord] {
        tasks.map { task in
            guard task.blockedBySyncID == task.id else { return task }
            var cleared = task
            cleared.blockedBySyncID = nil
            return cleared
        }
    }

    /// Every repair, in the order they have to run.
    static func repair(_ tasks: [SyncTaskRecord], sketches: [SyncSketchRecord]) -> [SyncTaskRecord] {
        clearDanglingSketchLinks(clearDanglingBlockers(clearSelfBlockers(tasks)), sketches: sketches)
    }
}
