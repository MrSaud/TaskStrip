import Foundation

/// Writes a backup the phone can restore.
///
/// The shape is BackupHelper.createBackupZip's: backup.json first, then every referenced file
/// under "media/". What matters more than the shape is what's *in* it — Android's restore calls
/// deleteAll() on every table before inserting, so a backup that left a section out wouldn't
/// merely fail to carry it, it would wipe it off the phone. Everything this app models is
/// written, and `credentials` and `tasks` are always present even when empty, because the
/// restore reads those two with getJSONArray and throws without them.
enum BackupExport {
    /// What the file is called. Matches the phone's naming so both ends of a transfer look alike,
    /// and sorts chronologically in a folder full of them.
    static func suggestedFileName(now: Date = .now, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "taskstrip_backup_\(formatter.string(from: now)).zip"
    }

    struct Contents {
        var tasks: [TaskItem] = []
        var notes: [Note] = []
        var storageItems: [StorageItem] = []
        var reminders: [Reminder] = []
        var credentials: [Credential] = []
    }

    struct Result {
        var archive: Data
        var fileCount: Int
        var filesMissing: Int
        var passwordsIncluded: Int
    }

    /// Builds the whole archive.
    ///
    /// `passphrase` empty means no passwords travel — the same choice Android makes, and for the
    /// same reason: a password in a file with nothing wrapped around it is worse than no password
    /// at all.
    static func archive(
        _ contents: Contents,
        passphrase: String = "",
        store: AttachmentStore,
        credentialStore: CredentialStore,
        timeZone: TimeZone = .current,
        now: Date = .now
    ) throws -> Result {
        var passwordsIncluded = 0
        let manifest = try manifestData(
            contents,
            passphrase: passphrase,
            credentialStore: credentialStore,
            timeZone: timeZone,
            passwordsIncluded: &passwordsIncluded
        )

        var entries = [ZipWriter.Entry(name: BackupArchive.manifestEntryName, data: manifest)]
        var missing = 0
        for path in mediaPaths(contents).sorted() {
            let url = store.url(forRelativePath: path)
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                // A strip can name a file that isn't there — an import that couldn't fetch it, or
                // a store moved out from under the app. The row still travels; the bytes can't.
                missing += 1
                continue
            }
            entries.append(
                ZipWriter.Entry(name: BackupArchive.mediaPrefix + path, data: data, compress: false)
            )
        }

        return Result(
            archive: ZipWriter.archive(entries),
            fileCount: entries.count - 1,
            filesMissing: missing,
            passwordsIncluded: passwordsIncluded
        )
    }

    /// Every file the backup should carry: a strip's attachments and the library's own files.
    static func mediaPaths(_ contents: Contents) -> Set<String> {
        var paths = Set(contents.tasks.flatMap { $0.attachments.map(\.path) })
        paths.formUnion(contents.storageItems.map(\.path))
        return paths.filter { !$0.isEmpty }
    }

    static func manifestData(
        _ contents: Contents,
        passphrase: String = "",
        credentialStore: CredentialStore,
        timeZone: TimeZone = .current,
        passwordsIncluded: inout Int
    ) throws -> Data {
        let indexOfTask = Dictionary(
            uniqueKeysWithValues: contents.tasks.enumerated().map { ($0.element.id, $0.offset) }
        )

        let manifest: [String: Any] = [
            "version": 1,
            "tasks": contents.tasks.map { json(for: $0, indexOfTask: indexOfTask, timeZone: timeZone) },
            // Always written, even empty: the restore reads this one with getJSONArray.
            "credentials": contents.credentials.map {
                json(for: $0, passphrase: passphrase, store: credentialStore, included: &passwordsIncluded)
            },
            "notes": contents.notes.map { ["text": $0.text, "createdAt": milliseconds($0.createdAt)] },
            "reminders": contents.reminders.map { json(for: $0, timeZone: timeZone) },
            "storageItems": contents.storageItems.map { json(for: $0) },
        ]
        return try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    }

    // MARK: - Rows

    private static func json(
        for task: TaskItem,
        indexOfTask: [UUID: Int],
        timeZone: TimeZone
    ) -> [String: Any] {
        var object: [String: Any] = [
            "title": task.title,
            // Dead on Android, superseded by tags — but its restore reads it with getString, and
            // getString on a missing key throws. An empty string costs nothing and keeps a
            // Mac-written backup restorable.
            "route": "",
            "notes": task.notes,
            "notesRtl": task.notesRtl,
            "priority": task.priority.rawValue,
            "orderIndex": task.orderIndex,
            "isDone": task.isDone,
            "isArchived": task.isArchived,
            "progress": task.progress,
            "createdAt": milliseconds(task.createdAt),
            "waitingOnName": task.waitingOnName,
            "tags": task.tags,
            "contacts": task.contacts.map { ["name": $0.name, "email": $0.email, "phone": $0.phone] },
            "links": task.links.map { ["url": $0.url, "label": $0.label] },
            "actionLog": task.actionLog.map {
                ["text": $0.text, "timestamp": milliseconds($0.timestamp)]
            },
        ]

        // The four lists Android keeps separately, rebuilt from the one this app keeps.
        for kind in AttachmentKind.allCases {
            object[kind.backupKey] = task.attachments.filter { $0.kind == kind }.map(\.path)
        }

        // The one field that isn't a real instant on the way out either — see
        // androidWallClock(from:in:).
        if let dueAt = task.dueAt { object["dueAt"] = androidWallClock(from: dueAt, in: timeZone) }
        if let completedAt = task.completedAt { object["completedAt"] = milliseconds(completedAt) }
        if let since = task.waitingOnSince { object["waitingOnSince"] = milliseconds(since) }
        if let days = task.waitingOnFollowUpDays { object["waitingOnFollowUpDays"] = days }
        if let minutes = task.reminderMinutesBefore { object["reminderMinutesBefore"] = minutes }
        if let interval = task.repeatIntervalDays { object["repeatIntervalDays"] = interval }
        // A position in this array, not an id — restored rows get fresh ids, so an id would point
        // at nothing. A blocker that isn't in the export is dropped rather than left dangling.
        if let blockedByID = task.blockedByID, let index = indexOfTask[blockedByID] {
            object["blockedByIndex"] = index
        }
        return object
    }

    private static func json(for reminder: Reminder, timeZone: TimeZone) -> [String: Any] {
        var object: [String: Any] = [
            "text": reminder.text,
            "description": reminder.details,
            // The other wall clock, for the same reason as a strip's due date.
            "triggerAt": androidWallClock(from: reminder.triggerAt, in: timeZone),
            "tag": reminder.tag,
            "tagEmoji": reminder.tagEmoji,
            "isDone": reminder.isDone,
            "createdAt": milliseconds(reminder.createdAt),
        ]
        if let lead = reminder.leadMinutesBefore { object["leadMinutesBefore"] = lead }
        if reminder.repeats, let amount = reminder.repeatAmount, let unit = reminder.repeatUnit {
            object["repeatAmount"] = amount
            object["repeatUnit"] = unit.rawValue
        }
        return object
    }

    private static func json(for item: StorageItem) -> [String: Any] {
        [
            "name": item.name,
            "path": item.path,
            "type": item.type.rawValue,
            "mimeType": item.mimeType,
            "sizeBytes": item.sizeBytes,
            "tag": item.tag,
            "tagEmoji": item.tagEmoji,
            "createdAt": milliseconds(item.createdAt),
        ]
    }

    private static func json(
        for credential: Credential,
        passphrase: String,
        store: CredentialStore,
        included: inout Int
    ) -> [String: Any] {
        var object: [String: Any] = [
            "title": credential.title,
            "username": credential.username,
            "url": credential.url,
            "notes": credential.notes,
            "createdAt": milliseconds(credential.createdAt),
        ]
        guard !passphrase.isEmpty,
              let password = store.password(for: credential.id),
              !password.isEmpty,
              let encrypted = BackupCrypto.encrypt(password, passphrase: passphrase)
        else { return object }

        object["passwordSalt"] = encrypted.salt
        object["passwordIv"] = encrypted.iv
        object["passwordCipher"] = encrypted.cipher
        included += 1
        return object
    }

    // MARK: - Times

    static func milliseconds(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// The inverse of BackupImport.dueDate(fromAndroidWallClock:in:).
    ///
    /// Android stores a due date as the digits on the clock, pinned to UTC, so the same backup
    /// shows the same date wherever it's opened. Writing a real instant instead would move every
    /// date by the local offset the moment the phone read it back.
    static func androidWallClock(from date: Date, in timeZone: TimeZone) -> Int {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let wallClock = local.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let instant = utc.date(from: wallClock) else { return milliseconds(date) }
        return milliseconds(instant)
    }
}
