import CloudKit
import XCTest
@testable import TaskStrips

final class SortKeyTests: XCTestCase {
    func testAKeyFitsBetweenAnyTwo() {
        var keys = [SortKey.between(nil, nil)]
        // Keep squeezing into the same gap: the case that makes naive schemes run out of room.
        for _ in 0..<200 {
            let key = SortKey.between(keys[0], keys.count > 1 ? keys[1] : nil)
            XCTAssertLessThan(keys[0], key)
            if keys.count > 1 { XCTAssertLessThan(key, keys[1]) }
            keys.insert(key, at: 1)
        }
        for _ in 0..<200 {
            let key = SortKey.between(nil, keys[0])
            XCTAssertLessThan(key, keys[0])
            keys.insert(key, at: 0)
        }
        XCTAssertEqual(keys, keys.sorted())
        XCTAssertFalse(keys.contains { $0.hasSuffix("0") })
    }

    func testSpreadKeysAreInOrderAndShort() {
        let keys = SortKey.spread(500, between: nil, nil)
        XCTAssertEqual(keys, keys.sorted())
        XCTAssertEqual(Set(keys).count, 500)
        XCTAssertLessThanOrEqual(keys.map(\.count).max() ?? 0, 3)
    }

    /// The point of the whole scheme: moving one strip rewrites one key.
    func testMovingOneStripReKeysOnlyThatStrip() {
        let keys = SortKey.spread(6, between: nil, nil)
        var board = zip(["a", "b", "c", "d", "e", "f"], keys).map { (id: $0, key: $1) }
        let moved = board.remove(at: 4)             // e to the top
        board.insert(moved, at: 0)

        let changes = SortKey.rekey(board)
        XCTAssertEqual(Array(changes.keys), ["e"])
        let newKey = changes["e"]!
        XCTAssertLessThan(newKey, board[1].key)
    }

    func testNewStripsGetKeysAroundTheirNeighbours() {
        let keys = SortKey.spread(2, between: nil, nil)
        let board = [(id: "a", key: keys[0]), (id: "new1", key: ""), (id: "new2", key: ""), (id: "b", key: keys[1])]
        let changes = SortKey.rekey(board)
        XCTAssertEqual(Set(changes.keys), ["new1", "new2"])
        let ordered = [keys[0], changes["new1"]!, changes["new2"]!, keys[1]]
        XCTAssertEqual(ordered, ordered.sorted())
    }

    /// Two devices can hand out the same key at the same moment; the next pass separates them.
    func testTwoStripsWithTheSameKeyAreSeparated() {
        let board = [(id: "a", key: "V"), (id: "b", key: "V"), (id: "c", key: "k")]
        let changes = SortKey.rekey(board)
        let final = board.map { changes[$0.id] ?? $0.key }
        XCTAssertEqual(final, final.sorted())
        XCTAssertEqual(Set(final).count, 3)
    }
}

final class RecordMergeTests: XCTestCase {
    private func record(_ values: [String: String], secret: [String: String] = [:]) -> CKRecord {
        let record = CKRecord(recordType: "Strip", recordID: CKRecord.ID(recordName: "x"))
        for (key, value) in values { record[key] = value }
        for (key, value) in secret { record.encryptedValues[key] = value }
        return record
    }

    /// Two devices, two different fields: both edits survive.
    func testEditsToDifferentFieldsBothSurvive() {
        let base = record(["priority": "LOW"], secret: ["title": "Old"])
        let local = record(["priority": "LOW"], secret: ["title": "New title"])
        let server = record(["priority": "URGENT"], secret: ["title": "Old"])

        let merged = RecordMerge.merge(base: base, local: local, server: server)
        XCTAssertEqual(merged.encryptedValues["title"] as? String, "New title")
        XCTAssertEqual(merged["priority"] as? String, "URGENT")
    }

    func testAFieldOnlyTheServerChangedKeepsTheServersValue() {
        let base = record(["done": "0"])
        let merged = RecordMerge.merge(base: base, local: record(["done": "0"]), server: record(["done": "1"]))
        XCTAssertEqual(merged["done"] as? String, "1")
    }

    /// Clearing a field is a change too, and has to win over the server's untouched value.
    func testClearingAFieldIsAnEdit() {
        let base = record(["dueAt": "monday"])
        let merged = RecordMerge.merge(base: base, local: record([:]), server: record(["dueAt": "monday"]))
        XCTAssertNil(merged["dueAt"])
    }

    func testNothingChangedMeansNothingToSend() {
        let base = record(["a": "1"], secret: ["t": "x"])
        XCTAssertTrue(RecordMerge.changedKeys(local: record(["a": "1"], secret: ["t": "x"]), base: base).isEmpty)
        XCTAssertEqual(RecordMerge.changedKeys(local: record(["a": "2"], secret: ["t": "x"]), base: base), ["a"])
    }
}

final class DeletionGuardTests: XCTestCase {
    func testEverydayDeletionsGoStraightThrough() {
        XCTAssertFalse(DeletionGuard.needsConfirmation(deleting: 1, ofSynced: 3))
        XCTAssertFalse(DeletionGuard.needsConfirmation(deleting: 4, ofSynced: 10))
        XCTAssertFalse(DeletionGuard.needsConfirmation(deleting: 10, ofSynced: 200))
    }

    /// An emptied store wants to delete everything; that has to be asked about.
    func testDeletingMostOfTheBoardIsHeld() {
        XCTAssertTrue(DeletionGuard.needsConfirmation(deleting: 40, ofSynced: 40))
        XCTAssertTrue(DeletionGuard.needsConfirmation(deleting: 6, ofSynced: 12))
        XCTAssertTrue(DeletionGuard.needsConfirmation(deleting: 21, ofSynced: 1000))
    }
}

final class RecordCacheTests: XCTestCase {
    func testARecordSurvivesARestartWithItsEncryptedValues() {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RecordCacheTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let record = CKRecord(recordType: "Strip", recordID: CloudSchema.recordID("page/1"))
        record["priority"] = "HIGH"
        record.encryptedValues["title"] = "Secret title"
        RecordCache(directory: directory).store(record)

        let reopened = RecordCache(directory: directory)
        let back = reopened.record(named: "page/1")
        XCTAssertEqual(back?["priority"] as? String, "HIGH")
        XCTAssertEqual(back?.encryptedValues["title"] as? String, "Secret title")
        XCTAssertEqual(reopened.records(ofType: "Strip").count, 1)

        reopened.remove(named: "page/1")
        XCTAssertNil(RecordCache(directory: directory).record(named: "page/1"))
    }
}
