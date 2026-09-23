#if DEBUG
import CloudKit
import Foundation

/// Puts docs/CloudKitSchema.md into CloudKit's **Development** environment.
///
/// Development creates record types and fields the first time a record uses them. So this saves
/// one fully filled sample of every type — every field set, every file attached — into a
/// throwaway zone, then deletes the zone. The schema stays; the samples don't. Nothing here runs
/// in a Release build, and nothing touches the Board zone.
///
/// Production is a separate step (Phase 7): the CloudKit Console copies this schema across.
enum SchemaSeeder {
    /// Read-only: how many records of each type each zone holds. `-InspectCloudZones`; Debug only.
    static func inspectZones(log: (String) -> Void) async {
        let database = CKContainer(identifier: CloudSchema.containerID).privateCloudDatabase
        do {
            let zones = try await database.allRecordZones()
            log("INSPECT zones: \(zones.map(\.zoneID.zoneName).sorted())")
            for zone in zones where zone.zoneID.zoneName != CKRecordZone.default().zoneID.zoneName {
                var counts: [String: Int] = [:]
                var token: CKServerChangeToken?
                var more = true
                while more {
                    let result = try await database.recordZoneChanges(inZoneWith: zone.zoneID, since: token)
                    for case .success(let modification) in result.modificationResultsByID.values {
                        counts[modification.record.recordType, default: 0] += 1
                    }
                    token = result.changeToken
                    more = result.moreComing
                }
                log("INSPECT \(zone.zoneID.zoneName): \(counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
            }
        } catch {
            log("INSPECT failed: \(error.localizedDescription)")
        }
    }

    /// Phase 6: removes the Board zone the sync test board used before it got a zone of its own,
    /// so the real board starts in an empty zone. `-EraseTestDataFromBoardZone`; Debug only.
    static func eraseLegacyTestZone(log: (String) -> Void) async {
        await eraseZone("Board", log: log)
    }

    /// The sync test board's own zone and all its test data. `-EraseBoardTestZone`; Debug only.
    static func eraseZone(_ name: String, log: (String) -> Void) async {
        let database = CKContainer(identifier: CloudSchema.containerID).privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: name, ownerName: CKCurrentUserDefaultName)
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
            log("ERASE \(name) zone deleted")
        } catch let error as CKError where error.code == .zoneNotFound {
            log("ERASE \(name) zone was already gone")
        } catch {
            log("ERASE failed: \(error.localizedDescription)")
        }
    }

    static let zoneName = "SchemaSeed"

    static func run(log: (String) -> Void) async {
        let container = CKContainer(identifier: CloudSchema.containerID)
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: zoneName)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "SchemaSeed-\(UUID().uuidString)")

        do {
            guard try await container.accountStatus() == .available else {
                log("SEED stopped: not signed into iCloud")
                return
            }
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            let file = scratch.appending(path: "sample.png")
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)

            _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
            let records = samples(in: zone.zoneID, file: file)
            let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
            var failures = 0
            for (id, outcome) in result.saveResults {
                if case .failure(let error) = outcome {
                    failures += 1
                    log("SEED \(id.recordName) failed: \(error.localizedDescription)")
                }
            }
            log("SEED saved \(records.count - failures) of \(records.count) record types")
            _ = try await database.modifyRecordZones(saving: [], deleting: [zone.zoneID])
            log(failures == 0 ? "SEED RESULT PASS" : "SEED RESULT FAIL")
        } catch {
            log("SEED error: \(error.localizedDescription)")
            _ = try? await database.modifyRecordZones(saving: [], deleting: [zone.zoneID])
        }
        try? FileManager.default.removeItem(at: scratch)
    }

    /// One of each type, written by the same code the sync will use, so the schema that lands is
    /// exactly the one CloudRecordCoding writes.
    private static func samples(in zoneID: CKRecordZone.ID, file: URL) -> [CKRecord] {
        func record(_ type: String, _ name: String) -> CKRecord {
            CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
        }
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let task = TaskItem(title: "Sample", orderIndex: 1, priority: .high)
        task.notes = "n"; task.notesRtl = true; task.dueAt = date; task.isDone = true
        task.isArchived = true; task.progress = 50; task.completedAt = date; task.blockedByID = UUID()
        task.waitingOnName = "w"; task.waitingOnSince = date; task.waitingOnFollowUpDays = 1
        task.linkedSketchID = "sketch"; task.tags = ["t"]; task.contacts = [TaskContact(name: "c")]
        task.links = [TaskLink(url: "https://example.com")]; task.actionLog = [TaskActionLogEntry(text: "l")]
        task.reminderMinutesBefore = 5; task.repeatIntervalDays = 7
        task.checklist = [TaskChecklistItem(text: "step", isDone: true, doneAt: date)]
        task.deferUntil = date
        task.sessions = [TaskWorkSession(startedAt: date, endedAt: date.addingTimeInterval(1800))]
        task.calendarEventID = "event"
        let strip = record(CloudSchema.RecordType.strip, task.id.uuidString)
        CloudRecordCoding.encode(task, sortKey: "V", into: strip)

        var attachment = TaskAttachment()
        attachment.name = "a"
        let attachmentRecord = record(CloudSchema.RecordType.attachment, attachment.id.uuidString)
        CloudRecordCoding.encode(attachment, stripID: task.id, file: file, into: attachmentRecord)
        // The reference has to point into the zone it's saved in.
        attachmentRecord[CloudSchema.Attachment.strip] = CKRecord.Reference(recordID: strip.recordID, action: .deleteSelf)

        let reminder = Reminder(text: "r", triggerAt: date, details: "d", leadMinutesBefore: 5,
                                repeatAmount: 1, repeatUnit: .weekly, tag: "t", tagEmoji: "🏷", isDone: true)
        let reminderRecord = record(CloudSchema.RecordType.reminder, reminder.id.uuidString)
        CloudRecordCoding.encode(reminder, into: reminderRecord)

        let note = Note(text: "n")
        let noteRecord = record(CloudSchema.RecordType.note, note.id.uuidString)
        CloudRecordCoding.encode(note, into: noteRecord)

        let item = StorageItem(name: "f", path: "p", type: .image, mimeType: "image/png", sizeBytes: 4, tag: "t", tagEmoji: "🏷")
        let itemRecord = record(CloudSchema.RecordType.storageFile, item.id.uuidString)
        CloudRecordCoding.encode(item, file: file, into: itemRecord)

        let credential = Credential(title: "c", username: "u", url: "https://example.com", notes: "n")
        let credentialRecord = record(CloudSchema.RecordType.credential, credential.id.uuidString)
        CloudRecordCoding.encode(credential, into: credentialRecord)

        let sketch = SketchNote(id: "sketch", name: "s", pageCount: 1, lastModified: date, createdAt: date, paper: .lined)
        let sketchRecord = record(CloudSchema.RecordType.sketch, sketch.id)
        CloudRecordCoding.encode(sketch, into: sketchRecord)
        let pageRecord = record(CloudSchema.RecordType.sketchPage, CloudSchema.SketchPage.recordName(sketch: sketch.id, number: 1))
        CloudRecordCoding.encodePage(sketch: sketch.id, number: 1, image: file, into: pageRecord)
        pageRecord[CloudSchema.SketchPage.sketch] = CKRecord.Reference(recordID: sketchRecord.recordID, action: .deleteSelf)

        return [strip, attachmentRecord, reminderRecord, noteRecord, itemRecord, credentialRecord, sketchRecord, pageRecord]
    }
}
#endif
