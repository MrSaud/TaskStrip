import CloudKit
import CryptoKit
import Foundation
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The board's sync through iCloud, built on CKSyncEngine — see docs/CloudKitSchema.md.
///
/// How it decides what to send: after every save it compares the board with the RecordCache —
/// the last copy of each record this device received from iCloud. Anything new or changed is
/// sent; anything in the cache but no longer on the board is deleted there, through the
/// DeletionGuard. Nothing is tracked by hand at each edit, so every path that changes the board —
/// the editor, a drag, a restore, the Share Extension — is covered the same way.
///
/// How it takes what arrives: each record is decoded onto the matching item (made if it's new),
/// its files copied into the store, and the cache updated first, so the save that follows finds
/// nothing to send back.
///
/// Phase 5: it only ever runs on the sync test board (AppLaunch.isSyncTesting).
@MainActor
final class BoardSync: ObservableObject {
    enum Status: Equatable {
        case off
        case syncing
        case upToDate(Date)
        /// Held by the DeletionGuard until the person says yes or no.
        case needsConfirmation(deletions: Int)
        /// Stopped for a reason the person should read — iCloud erased elsewhere, signed out.
        case stopped(String)
        case failed(String)
    }

    static let shared = BoardSync()

    @Published private(set) var status: Status = .off {
        didSet { if status != oldValue { log("status \(status)") } }
    }

    /// Counts and states only — never a title, a note or anything else a person wrote.
    private func log(_ line: String) {
        print("SYNC \(line)")
        fflush(stdout)
    }

    private var engine: CKSyncEngine?
    private var container: ModelContainer?
    private var context: ModelContext? { container?.mainContext }
    private let cache = RecordCache(directory: BoardLocation.syncDirectory.appending(path: "Records", directoryHint: .isDirectory))
    private var stateURL: URL { BoardLocation.syncDirectory.appending(path: "engine-state.json") }
    private var digestsURL: URL { BoardLocation.syncDirectory.appending(path: "page-digests.json") }
    private var orphansURL: URL { BoardLocation.syncDirectory.appending(path: "orphan-attachments.json") }
    private let defaults = UserDefaults(suiteName: "com.saud.taskstrip.synctest") ?? .standard
    private static let enabledKey = "sync.enabled"

    private var heldDeletions: [CKRecord.ID] = []
    private var isApplying = false
    private var diffTask: Task<Void, Never>?
    private var ticker: Timer?
    private var saveObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    private var attachments: AttachmentStore { .shared }
    private var sketches: SketchStore { .shared }

    // MARK: - Starting and stopping

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    /// Only ever on the sync test board, and never under a test suite.
    static var isAllowed: Bool {
        AppLaunch.isSyncTesting && !AppLaunch.isUITesting && !AppLaunch.isUnitTesting
    }

    func start(container: ModelContainer) {
        guard Self.isAllowed, engine == nil else { return }
        self.container = container
        guard isEnabled else {
            status = .off
            return
        }
        let database = CKContainer(identifier: CloudSchema.containerID).privateCloudDatabase
        var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: loadState(), delegate: self)
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if !engine.state.pendingDatabaseChanges.contains(where: { if case .saveZone = $0 { return true } else { return false } }) {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudSchema.zoneID))])
        }
        observeLocalChanges()
        registerForPushes()
        status = .syncing
        Task {
            try? await engine.fetchChanges()
            scheduleDiff(after: 0)
        }
    }

    func syncNow() async {
        guard let engine else { return }
        status = .syncing
        do {
            try await engine.fetchChanges()
            findLocalChanges()
            try await engine.sendChanges()
            status = .upToDate(.now)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Turns sync back on after it stopped, starting afresh: this device's board is uploaded as
    /// new, and whatever iCloud already has comes down and merges by record name.
    func turnOn() {
        guard let container else { return }
        resetLocalBookkeeping()
        isEnabled = true
        start(container: container)
    }

    /// Stops syncing on this device. This device keeps its board; iCloud keeps its copy.
    func turnOff() {
        stop(reason: nil)
    }

    /// The first erase: deletes iCloud's copy. Every other device finds the Board zone gone and
    /// stops syncing, keeping its own board — nobody re-uploads what was just erased. This device
    /// keeps its board too, and stops.
    func eraseICloudCopy() async {
        guard let engine else { return }
        engine.state.add(pendingDatabaseChanges: [.deleteZone(CloudSchema.zoneID)])
        do {
            try await engine.sendChanges()
            stop(reason: "iCloud's copy was erased. This device kept its board.")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// The deletions the brake held back: send them, or forget them (and let the next pass treat
    /// those items as still wanted by re-downloading them).
    func confirmHeldDeletions(_ yes: Bool) {
        guard let engine else { return }
        if yes {
            engine.state.add(pendingRecordZoneChanges: heldDeletions.map { .deleteRecord($0) })
        } else {
            // Forget iCloud's copy of them, and fetch it all again: they come back down.
            for id in heldDeletions { cache.remove(named: id.recordName) }
            resetFetchPosition()
        }
        heldDeletions = []
        status = .syncing
        Task { await syncNow() }
    }

    private func stop(reason: String?) {
        stopObserving()
        engine = nil
        isEnabled = false
        resetLocalBookkeeping()
        status = reason.map(Status.stopped) ?? .off
    }

    private func resetLocalBookkeeping() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: digestsURL)
    }

    private func resetFetchPosition() {
        try? FileManager.default.removeItem(at: stateURL)
        guard let container else { return }
        stopObserving()
        engine = nil
        start(container: container)
    }

    private func stopObserving() {
        diffTask?.cancel()
        ticker?.invalidate()
        ticker = nil
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        saveObserver = nil
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
    }

    private func registerForPushes() {
        #if os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #else
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    // MARK: - Noticing local changes

    private func observeLocalChanges() {
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleDiff(after: 1) }
        }
        // Every 30 s while open: sketches are files, not store saves, so they're looked for here;
        // and iCloud is asked for changes, in case its push is slow or never comes — waiting on
        // the push alone left a change a minute late on the first real try.
        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleDiff(after: 0)
                try? await self?.engine?.fetchChanges()
            }
        }
        // Coming back to the app is when someone looks at the board, so it's brought up to date.
        #if os(macOS)
        let becameActive = NSApplication.didBecomeActiveNotification
        #else
        let becameActive = UIApplication.didBecomeActiveNotification
        #endif
        activeObserver = NotificationCenter.default.addObserver(forName: becameActive, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in try? await self?.engine?.fetchChanges() }
        }
    }

    private func scheduleDiff(after seconds: Double) {
        diffTask?.cancel()
        diffTask = Task {
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard !Task.isCancelled else { return }
            findLocalChanges()
        }
    }

    /// Compares the board with the cache and queues what differs.
    func findLocalChanges() {
        // Nothing new is looked for while held deletions wait for an answer.
        guard let engine, !isApplying, heldDeletions.isEmpty else { return }
        let local = snapshot()
        var saves: [CKRecord.ID] = []
        for (name, item) in local {
            let base = cache.record(named: name)
            let record = build(item, onto: base?.copy() as? CKRecord, name: name)
            if base == nil || !RecordMerge.changedKeys(local: record, base: base).isEmpty || pageChanged(item, name: name) {
                saves.append(CloudSchema.recordID(name))
            }
        }
        let deletions = allCachedNames().filter { local[$0] == nil }.map(CloudSchema.recordID)

        let pending = Set(engine.state.pendingRecordZoneChanges.map(\.recordIDForComparison))
        let newSaves = saves.filter { !pending.contains($0) }
        if !newSaves.isEmpty || !deletions.isEmpty { log("local: \(newSaves.count) to save, \(deletions.count) to delete") }
        if !newSaves.isEmpty {
            engine.state.add(pendingRecordZoneChanges: newSaves.map { .saveRecord($0) })
        }
        if DeletionGuard.needsConfirmation(deleting: deletions.count, ofSynced: cache.count) {
            heldDeletions = deletions
            status = .needsConfirmation(deletions: deletions.count)
            return
        }
        let newDeletes = deletions.filter { !pending.contains($0) }
        if !newDeletes.isEmpty {
            engine.state.add(pendingRecordZoneChanges: newDeletes.map { .deleteRecord($0) })
        }
        // Sent now rather than whenever the system gets round to it: the other devices can only
        // see a change once it's in iCloud.
        if !newSaves.isEmpty || !newDeletes.isEmpty {
            Task { try? await engine.sendChanges() }
        }
    }

    private func allCachedNames() -> [String] {
        CloudSchema.RecordType.all.flatMap { cache.records(ofType: $0).map(\.recordID.recordName) }
    }

    // MARK: - The board as records

    private enum Item {
        case strip(TaskItem, sortKey: String)
        case attachment(TaskAttachment, strip: UUID)
        case reminder(Reminder)
        case note(Note)
        case storage(StorageItem)
        case credential(Credential)
        case sketch(SketchNote)
        case sketchPage(sketch: String, number: Int, file: URL)
    }

    /// Everything on the board, by record name.
    private func snapshot() -> [String: Item] {
        guard let context else { return [:] }
        var items: [String: Item] = [:]

        let strips = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? [])
            .filter { !$0.isTombstoned }
            .sorted { ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString) }
        let keyed = strips.map { (id: $0.id.uuidString, key: cachedSortKey($0.id.uuidString)) }
        let newKeys = SortKey.rekey(keyed)
        for (task, entry) in zip(strips, keyed) {
            items[entry.id] = .strip(task, sortKey: newKeys[entry.id] ?? entry.key)
            for attachment in task.attachments where attachments.exists(attachment) {
                items[attachment.id.uuidString] = .attachment(attachment, strip: task.id)
            }
        }
        for reminder in (try? context.fetch(FetchDescriptor<Reminder>())) ?? [] where !reminder.isTombstoned {
            items[reminder.id.uuidString] = .reminder(reminder)
        }
        for note in (try? context.fetch(FetchDescriptor<Note>())) ?? [] {
            items[note.id.uuidString] = .note(note)
        }
        for item in (try? context.fetch(FetchDescriptor<StorageItem>())) ?? [] where !item.isTombstoned {
            items[item.id.uuidString] = .storage(item)
        }
        for credential in (try? context.fetch(FetchDescriptor<Credential>())) ?? [] where !credential.isTombstoned {
            items[credential.id.uuidString] = .credential(credential)
        }
        for sketch in sketches.notes() {
            items[sketch.id] = .sketch(sketch)
            for page in sketches.pages(of: sketch.id) {
                let number = SketchStore.pageNumber(page)
                items[CloudSchema.SketchPage.recordName(sketch: sketch.id, number: number)] =
                    .sketchPage(sketch: sketch.id, number: number, file: page)
            }
        }
        return items
    }

    private func cachedSortKey(_ name: String) -> String {
        cache.record(named: name)?[CloudSchema.Strip.sortKey] as? String ?? ""
    }

    private func build(_ item: Item, onto base: CKRecord?, name: String) -> CKRecord {
        func record(_ type: String) -> CKRecord { base ?? CloudRecordCoding.newRecord(type: type, name: name) }
        switch item {
        case .strip(let task, let key):
            let r = record(CloudSchema.RecordType.strip)
            CloudRecordCoding.encode(task, sortKey: key, into: r)
            return r
        case .attachment(let attachment, let strip):
            let r = record(CloudSchema.RecordType.attachment)
            CloudRecordCoding.encode(attachment, stripID: strip, file: attachments.url(for: attachment), into: r)
            return r
        case .reminder(let reminder):
            let r = record(CloudSchema.RecordType.reminder)
            CloudRecordCoding.encode(reminder, into: r)
            return r
        case .note(let note):
            let r = record(CloudSchema.RecordType.note)
            CloudRecordCoding.encode(note, into: r)
            return r
        case .storage(let storage):
            let r = record(CloudSchema.RecordType.storageFile)
            let file = attachments.url(forRelativePath: storage.path)
            CloudRecordCoding.encode(storage, file: FileManager.default.fileExists(atPath: file.path) ? file : nil, into: r)
            return r
        case .credential(let credential):
            let r = record(CloudSchema.RecordType.credential)
            CloudRecordCoding.encode(credential, into: r)
            return r
        case .sketch(let sketch):
            let r = record(CloudSchema.RecordType.sketch)
            CloudRecordCoding.encode(sketch, into: r)
            return r
        case .sketchPage(let sketch, let number, let file):
            let r = record(CloudSchema.RecordType.sketchPage)
            CloudRecordCoding.encodePage(sketch: sketch, number: number, image: file, into: r)
            return r
        }
    }

    /// Looks the item up again when the engine asks for its record — it may have changed, or
    /// gone, since it was queued.
    private func currentRecord(for id: CKRecord.ID) -> CKRecord? {
        guard let item = snapshot()[id.recordName] else { return nil }
        return build(item, onto: cache.workingCopy(named: id.recordName), name: id.recordName)
    }

    // MARK: - Sketch page contents

    private func digest(of file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func loadDigests() -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: digestsURL))) ?? [:]
    }

    private func saveDigest(_ value: String?, for name: String) {
        var digests = loadDigests()
        digests[name] = value
        try? FileManager.default.createDirectory(at: BoardLocation.syncDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(digests).write(to: digestsURL, options: .atomic)
    }

    /// A page's pixels live in a file, so a redrawn page is found by its bytes, not its fields.
    private func pageChanged(_ item: Item, name: String) -> Bool {
        guard case .sketchPage(_, _, let file) = item else { return false }
        return digest(of: file) != loadDigests()[name]
    }

    // MARK: - Taking what arrives

    private func apply(_ modifications: [CKRecord], deletions: [(CKRecord.ID, String)]) {
        guard let context else { return }
        isApplying = true
        defer { isApplying = false }

        // Parents before children, so a strip exists before its files look for it.
        let order = [CloudSchema.RecordType.strip, CloudSchema.RecordType.sketch]
        let sorted = modifications.sorted { (order.firstIndex(of: $0.recordType) ?? 9) < (order.firstIndex(of: $1.recordType) ?? 9) }
        log("received \(modifications.count) changed, \(deletions.count) deleted")
        for record in sorted {
            cache.store(record)
            applyOne(record, in: context)
        }
        for (id, type) in deletions {
            cache.remove(named: id.recordName)
            delete(id.recordName, type: type, in: context)
        }
        adoptOrphanAttachments(in: context)
        if modifications.contains(where: { $0.recordType == CloudSchema.RecordType.strip }) || !deletions.isEmpty {
            reorderFromSortKeys(in: context)
        }
        try? context.save()
    }

    private func applyOne(_ record: CKRecord, in context: ModelContext) {
        let name = record.recordID.recordName
        switch record.recordType {
        case CloudSchema.RecordType.strip:
            guard let id = UUID(uuidString: name) else { return }
            let task = fetchTask(id, in: context) ?? {
                let made = TaskItem(title: "", orderIndex: Int.max / 2, id: id)
                context.insert(made)
                return made
            }()
            CloudRecordCoding.decode(record, into: task)

        case CloudSchema.RecordType.attachment:
            guard let decoded = CloudRecordCoding.decodeAttachment(record) else { return }
            if let task = fetchTask(decoded.stripID, in: context),
               let index = task.attachments.firstIndex(where: { $0.id == decoded.attachment.id }) {
                task.attachments[index].name = decoded.attachment.name
                return
            }
            guard let file = decoded.file, let copy = try? attachments.add(contentsOf: file, kind: decoded.attachment.kind) else { return }
            var attachment = decoded.attachment
            attachment.path = copy.path
            if let task = fetchTask(decoded.stripID, in: context) {
                task.attachments.append(attachment)
            } else {
                // Its strip hasn't arrived yet; the file is kept and joins it when it does.
                var orphans = loadOrphans()
                orphans[attachment.id.uuidString] = Orphan(attachment: attachment, stripID: decoded.stripID)
                saveOrphans(orphans)
            }

        case CloudSchema.RecordType.reminder:
            guard let id = UUID(uuidString: name) else { return }
            let reminder = fetch(Reminder.self, id: id, in: context) ?? {
                let made = Reminder(text: "", triggerAt: .now, id: id)
                context.insert(made)
                return made
            }()
            CloudRecordCoding.decode(record, into: reminder)
            ReminderScheduler.shared.schedule(for: reminder)

        case CloudSchema.RecordType.note:
            guard let id = UUID(uuidString: name) else { return }
            let note = fetch(Note.self, id: id, in: context) ?? {
                let made = Note(text: "", id: id)
                context.insert(made)
                return made
            }()
            CloudRecordCoding.decode(record, into: note)

        case CloudSchema.RecordType.storageFile:
            guard let id = UUID(uuidString: name) else { return }
            let existing = fetch(StorageItem.self, id: id, in: context)
            let item = existing ?? StorageItem(name: "", path: "", type: .document, id: id)
            let file = CloudRecordCoding.decode(record, into: item)
            if item.path.isEmpty || !FileManager.default.fileExists(atPath: attachments.url(forRelativePath: item.path).path),
               let file, let copy = try? attachments.add(contentsOf: file, kind: item.type.attachmentKind) {
                item.path = copy.path
            }
            if existing == nil { context.insert(item) }

        case CloudSchema.RecordType.credential:
            guard let id = UUID(uuidString: name) else { return }
            let credential = fetch(Credential.self, id: id, in: context) ?? {
                let made = Credential(title: "", id: id)
                context.insert(made)
                return made
            }()
            CloudRecordCoding.decode(record, into: credential)

        case CloudSchema.RecordType.sketch:
            if let sketchName = record.encryptedValues[CloudSchema.Sketch.name] as? String {
                sketches.setName(sketchName, of: name)
            }
            if let created = record[CloudSchema.Sketch.createdAt] as? Date {
                sketches.setCreated(created, of: name)
            }

        case CloudSchema.RecordType.sketchPage:
            guard let reference = record[CloudSchema.SketchPage.sketch] as? CKRecord.Reference,
                  let number = record[CloudSchema.SketchPage.number] as? Int64,
                  let file = (record[CloudSchema.SketchPage.image] as? CKAsset)?.fileURL,
                  let data = try? Data(contentsOf: file)
            else { return }
            let target = sketches.folder(of: reference.recordID.recordName).appending(path: "page\(number).png")
            try? sketches.write(data, to: target)
            saveDigest(digest(of: target), for: name)

        default:
            break
        }
    }

    private func delete(_ name: String, type: String, in context: ModelContext) {
        switch type {
        case CloudSchema.RecordType.strip:
            guard let id = UUID(uuidString: name), let task = fetchTask(id, in: context) else { return }
            let all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
            StripActions.delete(task, in: all, context: context)
        case CloudSchema.RecordType.attachment:
            guard let id = UUID(uuidString: name) else { return }
            for task in (try? context.fetch(FetchDescriptor<TaskItem>())) ?? [] {
                if let attachment = task.attachments.first(where: { $0.id == id }) {
                    attachments.remove(attachment)
                    task.attachments.removeAll { $0.id == id }
                }
            }
        case CloudSchema.RecordType.reminder:
            if let id = UUID(uuidString: name), let reminder = fetch(Reminder.self, id: id, in: context) {
                ReminderScheduler.shared.cancel(reminderID: reminder.id)
                context.delete(reminder)
            }
        case CloudSchema.RecordType.note:
            if let id = UUID(uuidString: name), let note = fetch(Note.self, id: id, in: context) { context.delete(note) }
        case CloudSchema.RecordType.storageFile:
            if let id = UUID(uuidString: name), let item = fetch(StorageItem.self, id: id, in: context) {
                attachments.remove(relativePath: item.path, kind: item.type.attachmentKind)
                context.delete(item)
            }
        case CloudSchema.RecordType.credential:
            if let id = UUID(uuidString: name), let credential = fetch(Credential.self, id: id, in: context) {
                context.delete(credential)
            }
        case CloudSchema.RecordType.sketch:
            try? FileManager.default.removeItem(at: sketches.folder(of: name))
        case CloudSchema.RecordType.sketchPage:
            let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            try? FileManager.default.removeItem(at: sketches.folder(of: parts[0]).appending(path: parts[1] + ".png"))
            saveDigest(nil, for: name)
        default:
            break
        }
    }

    /// Strips iCloud knows take the order of their sort keys; any this device added that haven't
    /// gone up yet stay just after the strip they followed here.
    private func reorderFromSortKeys(in context: ModelContext) {
        let local = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? [])
            .sorted { ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString) }
        var synced = local.filter { !cachedSortKey($0.id.uuidString).isEmpty }
        synced.sort { (cachedSortKey($0.id.uuidString), $0.id.uuidString) < (cachedSortKey($1.id.uuidString), $1.id.uuidString) }
        var result = synced
        var lastSynced: TaskItem?
        for task in local {
            if cachedSortKey(task.id.uuidString).isEmpty {
                let at = lastSynced.flatMap { anchor in result.firstIndex { $0.id == anchor.id } }.map { $0 + 1 } ?? 0
                result.insert(task, at: min(at, result.count))
                lastSynced = task
            } else {
                lastSynced = task
            }
        }
        BoardOrdering.renumber(result)
    }

    // MARK: - Attachments waiting for their strip

    private struct Orphan: Codable {
        var attachment: TaskAttachment
        var stripID: UUID
    }

    private func loadOrphans() -> [String: Orphan] {
        (try? JSONDecoder().decode([String: Orphan].self, from: Data(contentsOf: orphansURL))) ?? [:]
    }

    private func saveOrphans(_ orphans: [String: Orphan]) {
        try? FileManager.default.createDirectory(at: BoardLocation.syncDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(orphans).write(to: orphansURL, options: .atomic)
    }

    private func adoptOrphanAttachments(in context: ModelContext) {
        var orphans = loadOrphans()
        guard !orphans.isEmpty else { return }
        for (key, orphan) in orphans {
            guard let task = fetchTask(orphan.stripID, in: context) else { continue }
            if !task.attachments.contains(where: { $0.id == orphan.attachment.id }) {
                task.attachments.append(orphan.attachment)
            }
            orphans[key] = nil
        }
        saveOrphans(orphans)
    }

    // MARK: - Fetching models by id

    private func fetchTask(_ id: UUID, in context: ModelContext) -> TaskItem? {
        try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetch(_ type: Reminder.Type, id: UUID, in context: ModelContext) -> Reminder? {
        try? context.fetch(FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetch(_ type: Note.Type, id: UUID, in context: ModelContext) -> Note? {
        try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetch(_ type: StorageItem.Type, id: UUID, in context: ModelContext) -> StorageItem? {
        try? context.fetch(FetchDescriptor<StorageItem>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetch(_ type: Credential.Type, id: UUID, in context: ModelContext) -> Credential? {
        try? context.fetch(FetchDescriptor<Credential>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Engine state on disk

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        try? FileManager.default.createDirectory(at: BoardLocation.syncDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }

    // MARK: - Engine events

    fileprivate func handle(_ event: CKSyncEngine.Event, engine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                break
            case .signOut:
                stop(reason: "Signed out of iCloud. This device kept its board.")
            case .switchAccounts:
                stop(reason: "A different iCloud account signed in. This device kept its board.")
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == CloudSchema.zoneID {
                switch deletion.reason {
                case .deleted:
                    stop(reason: "iCloud's copy was erased on another device. This device kept its board.")
                case .purged:
                    stop(reason: "Task Strips' iCloud data was deleted in Settings. This device kept its board.")
                case .encryptedDataReset:
                    // The encrypted fields in iCloud can no longer be read: send everything again.
                    cache.removeAll()
                    engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudSchema.zoneID))])
                    scheduleDiff(after: 0)
                @unknown default:
                    stop(reason: "iCloud's copy went away. This device kept its board.")
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            apply(
                changes.modifications.map(\.record),
                deletions: changes.deletions.map { ($0.recordID, $0.recordType) }
            )

        case .sentRecordZoneChanges(let sent):
            log("sent \(sent.savedRecords.count) saved, \(sent.deletedRecordIDs.count) deleted, \(sent.failedRecordSaves.count) failed")
            for record in sent.savedRecords {
                cache.store(record)
                if record.recordType == CloudSchema.RecordType.sketchPage,
                   let file = (record[CloudSchema.SketchPage.image] as? CKAsset)?.fileURL {
                    saveDigest(digest(of: file), for: record.recordID.recordName)
                }
            }
            for id in sent.deletedRecordIDs { cache.remove(named: id.recordName) }
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []
            for failure in sent.failedRecordSaves {
                let id = failure.record.recordID
                switch failure.error.code {
                case .serverRecordChanged:
                    guard let server = failure.error.serverRecord else { continue }
                    // Laid over the server's copy, applied here, then saved again.
                    let merged = RecordMerge.merge(base: cache.record(named: id.recordName), local: failure.record, server: server)
                    cache.store(server)
                    if let context { isApplying = true; applyOne(merged, in: context); isApplying = false; try? context.save() }
                    retry.append(.saveRecord(id))
                case .zoneNotFound:
                    engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudSchema.zoneID))])
                    retry.append(.saveRecord(id))
                case .unknownItem:
                    // Deleted in iCloud while this device edited it: the edit wins, as a new record.
                    cache.remove(named: id.recordName)
                    retry.append(.saveRecord(id))
                default:
                    status = .failed(failure.error.localizedDescription)
                }
            }
            if !retry.isEmpty { engine.state.add(pendingRecordZoneChanges: retry) }

        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                status = .failed(failure.error.localizedDescription)
            }

        case .willFetchChanges, .willSendChanges:
            if case .needsConfirmation = status { break }
            status = .syncing

        case .didFetchChanges, .didSendChanges:
            if case .needsConfirmation = status { break }
            if case .failed = status { break }
            status = .upToDate(.now)

        default:
            break
        }
    }

    fileprivate func nextBatch(_ context: CKSyncEngine.SendChangesContext, engine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = engine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { [weak self] id in
            // Built at the moment of sending, from the item as it is now; nil drops a change for
            // an item that's gone since it was queued.
            await self?.currentRecord(for: id)
        }
    }
}

extension BoardSync: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run { self.handle(event, engine: syncEngine) }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await nextBatch(context, engine: syncEngine)
    }
}

private extension CKSyncEngine.PendingRecordZoneChange {
    var recordIDForComparison: CKRecord.ID {
        switch self {
        case .saveRecord(let id), .deleteRecord(let id): return id
        @unknown default: return CKRecord.ID(recordName: "")
        }
    }
}
