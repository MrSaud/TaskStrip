import SwiftData
import XCTest
@testable import TaskStrips

/// The export's real test is whether the phone can restore what it writes, which can't be run
/// here — so what's checked is everything that would stop it: the sections Android's restore
/// reads with getJSONArray/getString and would throw without, the two wall-clock fields, and that
/// the archive reads back through the same code that reads the phone's.
final class BackupExportTests: XCTestCase {
    private var temporaryRoots: [URL] = []
    private var credentialStore: CredentialStore!

    override func setUpWithError() throws {
        credentialStore = CredentialStore(ephemeral: true)
    }

    override func tearDownWithError() throws {
        for root in temporaryRoots { try? FileManager.default.removeItem(at: root) }
        temporaryRoots = []
    }

    private func makeStore() -> AttachmentStore {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "export-media-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryRoots.append(root)
        return AttachmentStore(root: root)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func sampleContents() -> BackupExport.Contents {
        let strip = TaskItem(title: "Renew passport", orderIndex: 0, priority: .urgent)
        strip.notes = "تجديد جواز السفر"
        strip.notesRtl = true
        strip.tags = ["admin", "travel"]
        strip.progress = 40
        strip.dueAt = Date(timeIntervalSince1970: 1_789_000_000)
        strip.createdAt = Date(timeIntervalSince1970: 1_787_000_000)
        strip.attachments = [
            TaskAttachment(kind: .image, path: "images/passport.jpg", name: "Image 1"),
            TaskAttachment(kind: .document, path: "documents/checklist.pdf", name: "checklist.pdf"),
        ]

        let blocked = TaskItem(title: "Book flights", orderIndex: 1)
        blocked.blockedByID = strip.id

        return BackupExport.Contents(
            tasks: [strip, blocked],
            notes: [Note(text: "Packing list", createdAt: Date(timeIntervalSince1970: 1_787_500_000))],
            storageItems: [
                StorageItem(name: "receipt.pdf", path: "documents/receipt.pdf", type: .document,
                            mimeType: "application/pdf", sizeBytes: 2048, tag: "Receipt", tagEmoji: "💳")
            ],
            reminders: [
                Reminder(text: "Renew the registration",
                         triggerAt: Date(timeIntervalSince1970: 1_788_000_000),
                         details: "Istimara", leadMinutesBefore: 1440,
                         repeatAmount: 1, repeatUnit: .yearly, tag: "Documents", tagEmoji: "📄")
            ],
            credentials: [Credential(title: "Consulate portal", username: "saud", url: "https://visa.example.com")]
        )
    }

    private func manifest(
        _ contents: BackupExport.Contents,
        passphrase: String = "",
        timeZone: TimeZone = .current
    ) throws -> [String: Any] {
        var included = 0
        let data = try BackupExport.manifestData(
            contents,
            passphrase: passphrase,
            credentialStore: credentialStore,
            timeZone: timeZone,
            passwordsIncluded: &included
        )
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - What the phone's restore insists on

    /// Android reads these two with getJSONArray, which throws on a missing key. An export
    /// without them wouldn't restore at all.
    func testTasksAndCredentialsAreAlwaysPresentEvenWhenEmpty() throws {
        let root = try manifest(BackupExport.Contents())
        XCTAssertNotNil(root["tasks"] as? [Any])
        XCTAssertNotNil(root["credentials"] as? [Any])
        XCTAssertEqual(root["version"] as? Int, 1)
    }

    /// Every key Android's restore reads with getString/getInt/getBoolean/getLong — each one
    /// throws if it isn't there.
    func testAStripCarriesEveryFieldTheRestoreRequires() throws {
        let root = try manifest(sampleContents())
        let strip = try XCTUnwrap((root["tasks"] as? [[String: Any]])?.first)

        for key in ["title", "route", "notes", "priority", "orderIndex", "isDone", "isArchived",
                    "progress", "images", "voiceNotes", "documents", "videos", "createdAt"] {
            XCTAssertNotNil(strip[key], "the restore reads \"\(key)\" and throws without it")
        }
        // route is dead on Android but still read with getString.
        XCTAssertEqual(strip["route"] as? String, "")
        XCTAssertEqual(strip["priority"] as? String, "URGENT")
    }

    func testTheOtherSectionsCarryTheirRequiredFields() throws {
        let root = try manifest(sampleContents())

        let note = try XCTUnwrap((root["notes"] as? [[String: Any]])?.first)
        XCTAssertNotNil(note["text"])
        XCTAssertNotNil(note["createdAt"])

        let reminder = try XCTUnwrap((root["reminders"] as? [[String: Any]])?.first)
        for key in ["text", "triggerAt", "createdAt"] { XCTAssertNotNil(reminder[key]) }

        let item = try XCTUnwrap((root["storageItems"] as? [[String: Any]])?.first)
        for key in ["name", "path", "type", "createdAt"] { XCTAssertNotNil(item[key]) }

        let credential = try XCTUnwrap((root["credentials"] as? [[String: Any]])?.first)
        for key in ["title", "username", "url", "notes", "createdAt"] { XCTAssertNotNil(credential[key]) }
    }

    /// The four lists Android keeps separately, rebuilt from the one this app keeps.
    func testAttachmentsAreSplitBackIntoTheirFourLists() throws {
        let root = try manifest(sampleContents())
        let strip = try XCTUnwrap((root["tasks"] as? [[String: Any]])?.first)

        XCTAssertEqual(strip["images"] as? [String], ["images/passport.jpg"])
        XCTAssertEqual(strip["documents"] as? [String], ["documents/checklist.pdf"])
        XCTAssertEqual(strip["voiceNotes"] as? [String], [])
        XCTAssertEqual(strip["videos"] as? [String], [])
    }

    /// A position in the array, not an id: restored rows get fresh ids on the phone.
    func testBlockedByTravelsAsAnIndex() throws {
        let root = try manifest(sampleContents())
        let tasks = try XCTUnwrap(root["tasks"] as? [[String: Any]])

        XCTAssertNil(tasks[0]["blockedByIndex"])
        XCTAssertEqual(tasks[1]["blockedByIndex"] as? Int, 0)
    }

    func testABlockerThatIsNotInTheExportIsDroppedRatherThanDangling() throws {
        var contents = BackupExport.Contents()
        let orphan = TaskItem(title: "Blocked by something archived elsewhere", orderIndex: 0)
        orphan.blockedByID = UUID()
        contents.tasks = [orphan]

        let root = try manifest(contents)
        let strip = try XCTUnwrap((root["tasks"] as? [[String: Any]])?.first)
        XCTAssertNil(strip["blockedByIndex"])
    }

    // MARK: - The two wall clocks

    /// The inverse of the conversion on the way in. Writing a real instant would move every due
    /// date by the local offset the moment the phone read it back — the bug 0718633 fixed,
    /// mirrored.
    func testADueDateIsWrittenAsAUTCPinnedWallClock() throws {
        let riyadh = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        var local = Calendar(identifier: .gregorian)
        local.timeZone = riyadh
        let due = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 15, minute: 30)))

        var contents = BackupExport.Contents()
        let strip = TaskItem(title: "Due", orderIndex: 0)
        strip.dueAt = due
        contents.tasks = [strip]

        let root = try manifest(contents, timeZone: riyadh)
        let written = try XCTUnwrap((root["tasks"] as? [[String: Any]])?.first?["dueAt"] as? Int)

        // Read back as Android reads it: the digits on the clock, interpreted in UTC.
        let asUTC = utc.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date(timeIntervalSince1970: Double(written) / 1000)
        )
        XCTAssertEqual(asUTC.year, 2026)
        XCTAssertEqual(asUTC.month, 9)
        XCTAssertEqual(asUTC.day, 10)
        XCTAssertEqual(asUTC.hour, 15)
        XCTAssertEqual(asUTC.minute, 30)
    }

    /// createdAt beside it is a true instant, and must not get the same treatment.
    func testCreatedAtIsWrittenAsARealInstant() throws {
        var contents = BackupExport.Contents()
        let strip = TaskItem(title: "Filed", orderIndex: 0, createdAt: Date(timeIntervalSince1970: 1_787_000_000))
        contents.tasks = [strip]

        let root = try manifest(contents, timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh")))
        XCTAssertEqual((root["tasks"] as? [[String: Any]])?.first?["createdAt"] as? Int, 1_787_000_000_000)
    }

    // MARK: - Round trip

    /// The strongest check available without a phone: everything written comes back through the
    /// same reader that reads Android's own backups.
    func testWhatIsExportedCanBeImportedAgain() throws {
        let store = makeStore()
        let result = try BackupExport.archive(
            sampleContents(),
            store: store,
            credentialStore: credentialStore,
            timeZone: .gmt
        )

        let summary = try BackupImport.parse(
            manifest: try BackupArchive.manifestData(inArchive: result.archive),
            timeZone: .gmt
        )

        XCTAssertEqual(summary.tasks.map(\.title), ["Renew passport", "Book flights"])
        XCTAssertEqual(summary.tasks.first?.priority, .urgent)
        XCTAssertEqual(summary.tasks.first?.notes, "تجديد جواز السفر")
        XCTAssertEqual(summary.tasks.first?.tags, ["admin", "travel"])
        XCTAssertEqual(summary.tasks.first?.dueAt, Date(timeIntervalSince1970: 1_789_000_000))
        XCTAssertEqual(summary.tasks.last?.blockedByIndex, 0)
        XCTAssertEqual(summary.notes.map(\.text), ["Packing list"])
        XCTAssertEqual(summary.reminders.map(\.text), ["Renew the registration"])
        XCTAssertEqual(summary.reminders.first?.repeatUnit, .yearly)
        XCTAssertEqual(summary.storageItems.map(\.name), ["receipt.pdf"])
        XCTAssertEqual(summary.credentials.map(\.title), ["Consulate portal"])
        XCTAssertTrue(summary.skippedSections.isEmpty)
    }

    func testTheManifestIsTheFirstEntry() throws {
        let result = try BackupExport.archive(
            sampleContents(),
            store: makeStore(),
            credentialStore: credentialStore
        )
        let entries = try BackupArchive.entries(inArchive: result.archive)
        XCTAssertEqual(entries.first?.name, "backup.json")
    }

    // MARK: - Files

    func testTheFilesTheStripsAndLibraryNameAreCarried() throws {
        let store = makeStore()
        try store.write(Data("a passport scan".utf8), toRelativePath: "images/passport.jpg")
        try store.write(Data("a receipt".utf8), toRelativePath: "documents/receipt.pdf")

        let result = try BackupExport.archive(
            sampleContents(),
            store: store,
            credentialStore: credentialStore
        )

        XCTAssertEqual(result.fileCount, 2)
        // checklist.pdf is named by a strip but isn't on disk.
        XCTAssertEqual(result.filesMissing, 1)

        let names = try BackupArchive.entries(inArchive: result.archive).map(\.name)
        XCTAssertTrue(names.contains("media/images/passport.jpg"))
        XCTAssertTrue(names.contains("media/documents/receipt.pdf"))

        let entry = try XCTUnwrap(
            try BackupArchive.entries(inArchive: result.archive).first { $0.name == "media/images/passport.jpg" }
        )
        XCTAssertEqual(
            try BackupArchive.data(for: entry, inArchive: result.archive),
            Data("a passport scan".utf8)
        )
    }

    /// A file that can't be read shouldn't cost the whole export — the row still travels.
    func testAMissingFileDoesNotStopTheExport() throws {
        let result = try BackupExport.archive(
            sampleContents(),
            store: makeStore(),
            credentialStore: credentialStore
        )
        XCTAssertEqual(result.fileCount, 0)
        XCTAssertEqual(result.filesMissing, 3)
        XCTAssertFalse(result.archive.isEmpty)
    }

    // MARK: - Passwords

    func testWithoutAPassphraseNoPasswordTravels() throws {
        let contents = sampleContents()
        let credential = try XCTUnwrap(contents.credentials.first)
        credentialStore.setPassword("hunter2", for: credential.id)

        let root = try manifest(contents)
        let written = try XCTUnwrap((root["credentials"] as? [[String: Any]])?.first)
        XCTAssertNil(written["passwordCipher"])
        XCTAssertNil(written["passwordSalt"])
        XCTAssertNil(written["passwordIv"])
    }

    func testWithAPassphraseThePasswordTravelsEncrypted() throws {
        let contents = sampleContents()
        let credential = try XCTUnwrap(contents.credentials.first)
        credentialStore.setPassword("hunter2", for: credential.id)

        let root = try manifest(contents, passphrase: "open sesame")
        let written = try XCTUnwrap((root["credentials"] as? [[String: Any]])?.first)

        let encrypted = BackupCrypto.Encrypted(
            salt: try XCTUnwrap(written["passwordSalt"] as? String),
            iv: try XCTUnwrap(written["passwordIv"] as? String),
            cipher: try XCTUnwrap(written["passwordCipher"] as? String)
        )
        XCTAssertEqual(BackupCrypto.decrypt(encrypted, passphrase: "open sesame"), "hunter2")
        XCTAssertNil(BackupCrypto.decrypt(encrypted, passphrase: "wrong"))
    }

    func testACredentialWithNoSavedPasswordCarriesNothingEvenWithAPassphrase() throws {
        let root = try manifest(sampleContents(), passphrase: "open sesame")
        let written = try XCTUnwrap((root["credentials"] as? [[String: Any]])?.first)
        XCTAssertNil(written["passwordCipher"])
    }
}
