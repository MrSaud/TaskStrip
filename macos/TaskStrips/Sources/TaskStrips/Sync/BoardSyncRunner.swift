import Foundation
import SwiftData

/// The sync, wired to this machine.
///
/// Mirrors BoardSyncRunner.kt. BoardSync decides what should happen; this reads the objects to hand
/// it and writes back what it decided. Everything with judgement in it stays over there, tested;
/// what is here is the store and filesystem work that only running it can prove.
///
/// Credentials travel without their passwords unless `passphrase` is given, which is the rule the
/// backup already follows: the Keychain's copy is this machine's alone, and the alternative to a
/// passphrase is writing secrets in the clear.
@MainActor
struct BoardSyncRunner {
    var context: ModelContext
    var transport: BoardTransport
    var attachments: AttachmentStore = .shared
    var sketches: SketchStore = .shared
    var credentials: CredentialStore = .shared
    var passphrase: String?

    func run(hasSyncedBefore: Bool, adoptsOnFirstSync: Bool) async throws -> BoardSyncOutcome {
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let reminders = try context.fetch(FetchDescriptor<Reminder>())
        let items = try context.fetch(FetchDescriptor<StorageItem>())
        let logins = try context.fetch(FetchDescriptor<Credential>())
        let sketchIDs = sketches.allIDsForSync()

        // Hashed once, up front. Every later question — what to upload, what a strip's attachments
        // are called, where an arriving hash already lives — is answered from this one pass rather
        // than by reading the same files again.
        var pathsByHash: [String: URL] = [:]
        // The store can turn a relative path into a URL but not back again, so both are kept. A
        // record says nothing about where this machine puts a file; the relative path is how this
        // machine names it, and an attachment row needs that rather than an absolute URL.
        var relativeByHash: [String: String] = [:]
        func hashed(_ url: URL, relative: String? = nil) -> String? {
            guard let hash = try? SyncFileStore.hash(contentsOf: url) else { return nil }
            if pathsByHash[hash] == nil { pathsByHash[hash] = url }
            if let relative, relativeByHash[hash] == nil { relativeByHash[hash] = relative }
            return hash
        }

        let syncIDByLocalID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.id.uuidString) })
        let sketchSyncIDByFolder = Dictionary(uniqueKeysWithValues: sketchIDs.map { ($0, sketches.syncID(of: $0)) })
        let folderBySketchSyncID = Dictionary(uniqueKeysWithValues: sketchSyncIDByFolder.map { ($0.value, $0.key) })

        let taskRecords = tasks.map { task in
            BoardRecords.record(
                for: task,
                attachments: task.attachments.compactMap { attachment in
                    let url = attachments.url(for: attachment)
                    guard let hash = hashed(url, relative: attachment.path) else { return nil }
                    return SyncAttachment(hash: hash, name: attachment.name, kind: attachment.kind.rawValue)
                },
                syncIDOfTask: { syncIDByLocalID[$0] },
                syncIDOfSketch: { sketchSyncIDByFolder[$0] }
            )
        }

        let local = BoardSnapshot(
            tasks: taskRecords,
            reminders: reminders.map(BoardRecords.record(for:)),
            storage: items.map { item in
                BoardRecords.record(
                    for: item,
                    hash: hashed(attachments.url(forRelativePath: item.path), relative: item.path) ?? ""
                )
            },
            credentials: logins.map { BoardRecords.record(for: $0, password: portablePassword(for: $0)) },
            sketches: sketchIDs.map { id in
                SyncSketchRecord(
                    id: sketchSyncIDByFolder[id] ?? sketches.syncID(of: id),
                    updatedAt: sketches.isDeleted(id)
                        ? sketches.deletedAt(of: id)
                        : BoardRecords.millis(sketches.lastModified(of: id)),
                    isDeleted: sketches.isDeleted(id),
                    name: sketches.name(of: id) ?? "",
                    pages: sketches.pages(of: id).compactMap { hashed($0) },
                    createdAt: BoardRecords.millis(sketches.createdAt(of: id))
                )
            }
        )

        var landed: [String: (URL, String)] = [:]
        let outcome = try await BoardSync(transport: transport).run(
            local: local,
            localHashes: Set(pathsByHash.keys),
            hasSyncedBefore: hasSyncedBefore,
            adoptsOnFirstSync: adoptsOnFirstSync,
            readFile: { hash in
                guard let url = pathsByHash[hash] else { throw CocoaError(.fileNoSuchFile) }
                return try Data(contentsOf: url)
            },
            writeFile: { hash, data in
                // Named by the hash rather than by anything the record said. A file's own name is
                // the record's business and can differ between devices; where the bytes sit is
                // this machine's, and one name per content keeps a second copy from ever landing.
                let relative = "sync/\(hash)"
                try attachments.write(data, toRelativePath: relative)
                landed[hash] = (attachments.url(forRelativePath: relative), relative)
            }
        )

        for (hash, arrival) in landed {
            pathsByHash[hash] = arrival.0
            relativeByHash[hash] = arrival.1
        }
        apply(local: local, outcome: outcome, pathsByHash: pathsByHash,
              relativeByHash: relativeByHash, folderBySketchSyncID: folderBySketchSyncID)
        return outcome
    }

    /// Only what actually differs is written — a sync that changed nothing must not touch a single
    /// object, or every sync wakes every view watching the store.
    private func apply(
        local: BoardSnapshot,
        outcome: BoardSyncOutcome,
        pathsByHash: [String: URL],
        relativeByHash: [String: String],
        folderBySketchSyncID: [String: String]
    ) {
        applyTasks(local: local, outcome: outcome, relativeByHash: relativeByHash,
                   folderBySketchSyncID: folderBySketchSyncID)
        applyReminders(local: local, outcome: outcome)
        applyStorage(local: local, outcome: outcome, relativeByHash: relativeByHash)
        applyCredentials(local: local, outcome: outcome)
        applySketches(local: local, outcome: outcome, pathsByHash: pathsByHash,
                      folderBySketchSyncID: folderBySketchSyncID)
    }

    private func applyTasks(
        local: BoardSnapshot,
        outcome: BoardSyncOutcome,
        relativeByHash: [String: String],
        folderBySketchSyncID: [String: String]
    ) {
        let existing = Dictionary(
            (try? context.fetch(FetchDescriptor<TaskItem>()))?.map { ($0.id.uuidString, $0) } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        let plan = SyncBoardPlan.plan(
            localByID: Dictionary(uniqueKeysWithValues: local.tasks.map { ($0.id, $0) }),
            merged: outcome.merged.tasks,
            id: { $0.id },
            isDeleted: { $0.isDeleted }
        )

        for record in plan.insert + plan.update {
            let task: TaskItem
            if let here = existing[record.id] {
                task = here
            } else {
                guard let made = BoardRecords.newTask(from: record) else { continue }
                context.insert(made)
                task = made
            }
            BoardRecords.apply(
                record, to: task,
                localIDOfSyncID: { UUID(uuidString: $0) },
                localSketchIDOf: { folderBySketchSyncID[$0] }
            )
            // Only the attachments whose bytes are actually here. One that hasn't landed is left
            // out rather than pointed at nothing; the next sync adds it once the file arrives.
            task.attachments = record.attachments.compactMap { attachment -> TaskAttachment? in
                guard let relative = relativeByHash[attachment.hash] else { return nil }
                return TaskAttachment(
                    kind: AttachmentKind(rawValue: attachment.kind) ?? .document,
                    path: relative,
                    name: attachment.name
                )
            }
        }
        for id in plan.delete {
            // Written as a tombstone, not removed: this machine has to be able to tell the *next*
            // device about the delete too.
            existing[id].map { $0.isTombstoned = true }
        }
    }

    private func applyReminders(local: BoardSnapshot, outcome: BoardSyncOutcome) {
        let existing = Dictionary(
            (try? context.fetch(FetchDescriptor<Reminder>()))?.map { ($0.id.uuidString, $0) } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        let plan = SyncBoardPlan.plan(
            localByID: Dictionary(uniqueKeysWithValues: local.reminders.map { ($0.id, $0) }),
            merged: outcome.merged.reminders,
            id: { $0.id },
            isDeleted: { $0.isDeleted }
        )
        for record in plan.insert + plan.update {
            if let here = existing[record.id] {
                BoardRecords.apply(record, to: here)
            } else if let made = BoardRecords.newReminder(from: record) {
                context.insert(made)
                BoardRecords.apply(record, to: made)
            }
        }
        for id in plan.delete { existing[id].map { $0.isTombstoned = true } }
    }

    /// A library item is only worth a row once its bytes are somewhere: one whose file hasn't
    /// landed is skipped rather than written with a path that opens nothing — written, the row
    /// would look up to date and no later sync would fix it.
    private func applyStorage(local: BoardSnapshot, outcome: BoardSyncOutcome, relativeByHash: [String: String]) {
        let existing = Dictionary(
            (try? context.fetch(FetchDescriptor<StorageItem>()))?.map { ($0.id.uuidString, $0) } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        let plan = SyncBoardPlan.plan(
            localByID: Dictionary(uniqueKeysWithValues: local.storage.map { ($0.id, $0) }),
            merged: outcome.merged.storage,
            id: { $0.id },
            isDeleted: { $0.isDeleted }
        )
        for record in plan.insert + plan.update {
            if let here = existing[record.id] {
                BoardRecords.apply(record, to: here)
            } else {
                guard let id = UUID(uuidString: record.id),
                      let relative = relativeByHash[record.hash]
                else { continue }
                let item = StorageItem(
                    name: record.name,
                    path: relative,
                    type: StorageItemType(rawValue: record.type) ?? .document,
                    id: id,
                    createdAt: BoardRecords.date(record.createdAt)
                )
                context.insert(item)
                BoardRecords.apply(record, to: item)
            }
        }
        for id in plan.delete { existing[id].map { $0.isTombstoned = true } }
    }

    /// The password crosses under the user's passphrase and is kept here in the Keychain, so it is
    /// decrypted and re-stored on the way in. With no passphrase, or a record carrying no secret,
    /// whatever is already in the Keychain is left alone: losing a password to a sync that couldn't
    /// read it would be losing data, and keeping the old one never is.
    private func applyCredentials(local: BoardSnapshot, outcome: BoardSyncOutcome) {
        let existing = Dictionary(
            (try? context.fetch(FetchDescriptor<Credential>()))?.map { ($0.id.uuidString, $0) } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        let plan = SyncBoardPlan.plan(
            localByID: Dictionary(uniqueKeysWithValues: local.credentials.map { ($0.id, $0) }),
            merged: outcome.merged.credentials,
            id: { $0.id },
            isDeleted: { $0.isDeleted }
        )
        for record in plan.insert + plan.update {
            let credential: Credential
            if let here = existing[record.id] {
                credential = here
            } else {
                guard let id = UUID(uuidString: record.id) else { continue }
                let made = Credential(title: record.title, id: id,
                                      createdAt: BoardRecords.date(record.createdAt))
                context.insert(made)
                credential = made
            }
            BoardRecords.apply(record, to: credential)
            if let secret = arrivingPassword(record) {
                _ = credentials.setPassword(secret, for: credential.id)
            }
        }
        for id in plan.delete { existing[id].map { $0.isTombstoned = true } }
    }

    /// Pages are written in the record's order rather than the order they arrived, because page
    /// numbering is a local detail and the record is what says which page is which. A note whose
    /// pages haven't all landed is left alone entirely — half a drawing is worse than yesterday's
    /// whole one, and the next sync writes it properly once the rest is here.
    private func applySketches(
        local: BoardSnapshot,
        outcome: BoardSyncOutcome,
        pathsByHash: [String: URL],
        folderBySketchSyncID: [String: String]
    ) {
        let here = Dictionary(uniqueKeysWithValues: local.sketches.map { ($0.id, $0) })
        for record in outcome.merged.sketches where record != here[record.id] {
            let folder = folderBySketchSyncID[record.id] ?? "note_\(record.createdAt)"

            if record.isDeleted {
                if !sketches.pages(of: folder).isEmpty { sketches.deleteNote(folder) }
                sketches.setSyncID(record.id, of: folder)
                continue
            }

            let sources = record.pages.map { pathsByHash[$0] }
            guard !sources.contains(where: { $0 == nil }) else { continue }

            sketches.setSyncID(record.id, of: folder)
            for page in sketches.pages(of: folder) { sketches.deletePage(page) }
            for (index, source) in sources.compactMap({ $0 }).enumerated() {
                guard let data = try? Data(contentsOf: source) else { continue }
                try? sketches.write(data, to: sketches.folder(of: folder).appending(path: "page\(index + 1).png"))
            }
            if !record.name.isEmpty { sketches.setName(record.name, of: folder) }
        }
    }

    private func portablePassword(for credential: Credential) -> BoardRecords.PortablePassword? {
        guard let passphrase, let plain = credentials.password(for: credential.id), !plain.isEmpty
        else { return nil }
        guard let sealed = BackupCrypto.encrypt(plain, passphrase: passphrase) else { return nil }
        return BoardRecords.PortablePassword(salt: sealed.salt, iv: sealed.iv, cipher: sealed.cipher)
    }

    private func arrivingPassword(_ record: SyncCredentialRecord) -> String? {
        guard let passphrase, record.hasPassword else { return nil }
        return BackupCrypto.decrypt(
            BackupCrypto.Encrypted(
                salt: record.passwordSalt ?? "",
                iv: record.passwordIv ?? "",
                cipher: record.passwordCipher ?? ""
            ),
            passphrase: passphrase
        )
    }
}
