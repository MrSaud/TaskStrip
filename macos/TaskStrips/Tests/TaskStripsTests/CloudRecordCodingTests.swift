import CloudKit
import SwiftData
import XCTest
@testable import TaskStrips

/// Every model through its CloudKit record and back, as docs/CloudKitSchema.md says it goes.
/// Offline: a CKRecord can be built and read without a container.
final class CloudRecordCodingTests: XCTestCase {
    private var context: ModelContext!

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    private func fullStrip() -> TaskItem {
        let task = TaskItem(title: "Renew passport", orderIndex: 7, priority: .urgent)
        task.notes = "Bring two photos"
        task.notesRtl = true
        task.dueAt = Date(timeIntervalSince1970: 1_800_000_000)
        task.isDone = true
        task.completedAt = Date(timeIntervalSince1970: 1_800_000_100)
        task.progress = 40
        task.blockedByID = UUID()
        task.waitingOnName = "Embassy"
        task.waitingOnSince = Date(timeIntervalSince1970: 1_799_000_000)
        task.waitingOnFollowUpDays = 3
        task.linkedSketchID = "note_1700000000000"
        task.tags = ["home", "papers"]
        task.contacts = [TaskContact(name: "Clerk", email: "c@example.com", phone: "123")]
        task.links = [TaskLink(url: "https://example.com", label: "Form")]
        task.actionLog = [TaskActionLogEntry(text: "Called", timestamp: Date(timeIntervalSince1970: 1_799_500_000))]
        task.reminderMinutesBefore = 30
        task.repeatIntervalDays = 365
        context.insert(task)
        return task
    }

    func testAStripComesBackWithEveryField() {
        let original = fullStrip()
        let record = CloudRecordCoding.newRecord(type: CloudSchema.RecordType.strip, name: original.id.uuidString)
        CloudRecordCoding.encode(original, into: record)

        let copy = TaskItem(title: "", orderIndex: 0)
        CloudRecordCoding.decode(record, into: copy)

        XCTAssertEqual(copy.title, original.title)
        XCTAssertEqual(copy.notes, original.notes)
        XCTAssertEqual(copy.notesRtl, true)
        XCTAssertEqual(copy.priority, .urgent)
        XCTAssertEqual(copy.dueAt, original.dueAt)
        XCTAssertTrue(copy.isDone)
        XCTAssertEqual(copy.completedAt, original.completedAt)
        XCTAssertEqual(copy.progress, 40)
        XCTAssertEqual(copy.blockedByID, original.blockedByID)
        XCTAssertEqual(copy.waitingOnName, "Embassy")
        XCTAssertEqual(copy.waitingOnSince, original.waitingOnSince)
        XCTAssertEqual(copy.waitingOnFollowUpDays, 3)
        XCTAssertEqual(copy.linkedSketchID, original.linkedSketchID)
        XCTAssertEqual(copy.tags, ["home", "papers"])
        XCTAssertEqual(copy.contacts, original.contacts)
        XCTAssertEqual(copy.links, original.links)
        XCTAssertEqual(copy.actionLog, original.actionLog)
        XCTAssertEqual(copy.reminderMinutesBefore, 30)
        XCTAssertEqual(copy.repeatIntervalDays, 365)
        XCTAssertEqual(copy.createdAt, original.createdAt)
    }

    /// The whole point of rule 4: nothing a person wrote is in a plain field.
    func testWhatAPersonWroteIsOnlyInEncryptedFields() {
        let record = CloudRecordCoding.newRecord(type: CloudSchema.RecordType.strip, name: UUID().uuidString)
        CloudRecordCoding.encode(fullStrip(), into: record)

        for key in CloudSchema.Strip.encrypted {
            XCTAssertNil(record[key], "\(key) must not be stored in the clear")
            XCTAssertNotNil(record.encryptedValues[key], "\(key) is missing from the encrypted values")
        }
        XCTAssertEqual(record[CloudSchema.Strip.priority] as? String, "URGENT")
    }

    func testEveryRecordSaysWhichSchemaWroteIt() {
        let record = CloudRecordCoding.newRecord(type: CloudSchema.RecordType.note, name: UUID().uuidString)
        CloudRecordCoding.encode(Note(text: "hello"), into: record)
        XCTAssertEqual(record[CloudSchema.schemaVersionKey] as? Int64, CloudSchema.version)
    }

    /// Rule 3: an older device editing a newer device's record keeps what it doesn't understand.
    func testFieldsFromANewerVersionSurviveAnEdit() {
        let record = CloudRecordCoding.newRecord(type: CloudSchema.RecordType.strip, name: UUID().uuidString)
        record["colour"] = "teal"
        record[CloudSchema.schemaVersionKey] = Int64(5)

        CloudRecordCoding.encode(fullStrip(), into: record)

        XCTAssertEqual(record["colour"] as? String, "teal")
        XCTAssertEqual(record[CloudSchema.schemaVersionKey] as? Int64, 5)
    }

    /// Clearing a due date on one device has to clear it on the others.
    func testAClearedDueDateIsClearedOnDecode() {
        let task = fullStrip()
        task.dueAt = nil
        let record = CloudRecordCoding.newRecord(type: CloudSchema.RecordType.strip, name: task.id.uuidString)
        CloudRecordCoding.encode(task, into: record)

        let copy = TaskItem(title: "x", orderIndex: 0)
        copy.dueAt = .now
        CloudRecordCoding.decode(record, into: copy)
        XCTAssertNil(copy.dueAt)
    }

    func testAnAttachmentPointsAtItsStripAndCarriesItsFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        try Data("pdf".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let strip = UUID()
        var attachment = TaskAttachment()
        attachment.kind = .document
        attachment.name = "Scan.pdf"

        let record = CloudRecordCoding.newRecord(type: CloudSchema.RecordType.attachment, name: attachment.id.uuidString)
        CloudRecordCoding.encode(attachment, stripID: strip, file: file, into: record)

        let decoded = try XCTUnwrap(CloudRecordCoding.decodeAttachment(record))
        XCTAssertEqual(decoded.stripID, strip)
        XCTAssertEqual(decoded.attachment.id, attachment.id)
        XCTAssertEqual(decoded.attachment.name, "Scan.pdf")
        XCTAssertEqual(decoded.attachment.kind, .document)
        XCTAssertEqual(decoded.file, file)
        XCTAssertEqual((record[CloudSchema.Attachment.strip] as? CKRecord.Reference)?.action, .deleteSelf)
    }

    func testAReminderComesBack() {
        let original = Reminder(
            text: "Pay rent", triggerAt: Date(timeIntervalSince1970: 1_800_000_000), details: "Landlord",
            leadMinutesBefore: 60, repeatAmount: 1, repeatUnit: .monthly, tag: "Home", tagEmoji: "🏠", isDone: true
        )
        let record = CloudRecordCoding.newRecord(type: CloudSchema.RecordType.reminder, name: original.id.uuidString)
        CloudRecordCoding.encode(original, into: record)

        let copy = Reminder(text: "", triggerAt: .now)
        CloudRecordCoding.decode(record, into: copy)
        XCTAssertEqual(copy.text, "Pay rent")
        XCTAssertEqual(copy.details, "Landlord")
        XCTAssertEqual(copy.triggerAt, original.triggerAt)
        XCTAssertEqual(copy.leadMinutesBefore, 60)
        XCTAssertEqual(copy.repeatAmount, 1)
        XCTAssertEqual(copy.repeatUnit, .monthly)
        XCTAssertEqual(copy.tag, "Home")
        XCTAssertEqual(copy.tagEmoji, "🏠")
        XCTAssertTrue(copy.isDone)
        for key in CloudSchema.Reminder.encrypted { XCTAssertNil(record[key]) }
    }

    func testAStorageFileComesBack() {
        let original = StorageItem(name: "Receipt.pdf", path: "documents/x.pdf", type: .document,
                                   mimeType: "application/pdf", sizeBytes: 2048, tag: "Tax", tagEmoji: "💳")
        let record = CloudRecordCoding.newRecord(type: CloudSchema.RecordType.storageFile, name: original.id.uuidString)
        CloudRecordCoding.encode(original, file: nil, into: record)

        let copy = StorageItem(name: "", path: "", type: .image)
        CloudRecordCoding.decode(record, into: copy)
        XCTAssertEqual(copy.name, "Receipt.pdf")
        XCTAssertEqual(copy.type, .document)
        XCTAssertEqual(copy.mimeType, "application/pdf")
        XCTAssertEqual(copy.sizeBytes, 2048)
        XCTAssertEqual(copy.tag, "Tax")
        XCTAssertEqual(copy.tagEmoji, "💳")
    }

    /// And the password is nowhere in the record — it lives in iCloud Keychain.
    func testACredentialComesBackWithoutAPassword() {
        let original = Credential(title: "Bank", username: "saud", url: "https://bank.example", notes: "PIN in safe")
        let record = CloudRecordCoding.newRecord(type: CloudSchema.RecordType.credential, name: original.id.uuidString)
        CloudRecordCoding.encode(original, into: record)

        let copy = Credential(title: "")
        CloudRecordCoding.decode(record, into: copy)
        XCTAssertEqual(copy.title, "Bank")
        XCTAssertEqual(copy.username, "saud")
        XCTAssertEqual(copy.url, "https://bank.example")
        XCTAssertEqual(copy.notes, "PIN in safe")
        XCTAssertFalse(record.allKeys().contains { $0.localizedCaseInsensitiveContains("password") })
        XCTAssertFalse(record.encryptedValues.allKeys().contains { $0.localizedCaseInsensitiveContains("password") })
    }

    func testASketchPageIsNamedAfterItsSketch() {
        let record = CloudRecordCoding.newRecord(
            type: CloudSchema.RecordType.sketchPage,
            name: CloudSchema.SketchPage.recordName(sketch: "note_1", number: 2)
        )
        CloudRecordCoding.encodePage(sketch: "note_1", number: 2, image: nil, into: record)
        XCTAssertEqual(record.recordID.recordName, "note_1/page2")
        XCTAssertEqual(record[CloudSchema.SketchPage.number] as? Int64, 2)
        XCTAssertEqual((record[CloudSchema.SketchPage.sketch] as? CKRecord.Reference)?.recordID.recordName, "note_1")
    }
}
