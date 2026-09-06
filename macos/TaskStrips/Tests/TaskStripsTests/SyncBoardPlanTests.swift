import XCTest
@testable import TaskStrips

/// Mirrors SyncBoardPlanTest.kt case for case. These are the decisions that can quietly lose a
/// strip, so both devices are held to the same ones.
final class SyncBoardPlanTests: XCTestCase {

    private func task(_ id: String, _ title: String = "", at: Int64 = 1, deleted: Bool = false) -> SyncTaskRecord {
        SyncTaskRecord(id: id, updatedAt: at, isDeleted: deleted, title: title)
    }

    private func plan(_ local: [SyncTaskRecord], _ merged: [SyncTaskRecord]) -> BoardPlan<SyncTaskRecord> {
        SyncBoardPlan.plan(
            localByID: Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) }),
            merged: merged,
            id: { $0.id },
            isDeleted: { $0.isDeleted }
        )
    }

    // MARK: - Insert, update, delete

    func testARowTheMergeKnowsAndThisDeviceDoesntIsAnInsert() {
        let result = plan([], [task("a", "New")])

        XCTAssertEqual(result.insert.map(\.title), ["New"])
        XCTAssertTrue(result.update.isEmpty)
        XCTAssertTrue(result.delete.isEmpty)
    }

    func testARowTheMergeChangedIsAnUpdate() {
        let result = plan([task("a", "Old")], [task("a", "New", at: 2)])

        XCTAssertEqual(result.update.map(\.title), ["New"])
        XCTAssertTrue(result.insert.isEmpty)
    }

    /// A sync that changed nothing must write nothing, or every sync churns the store and every
    /// view watching it.
    func testARowThatIsAlreadyIdenticalIsLeftAlone() {
        let same = task("a", "Same")

        XCTAssertTrue(plan([same], [same]).isEmpty)
    }

    func testATombstoneForARowThisDeviceHoldsIsADelete() {
        let result = plan([task("a", "Here")], [task("a", at: 2, deleted: true)])

        XCTAssertEqual(result.delete, ["a"])
        XCTAssertTrue(result.insert.isEmpty)
    }

    /// Inserting a row purely to delete it would be work for nobody.
    func testATombstoneForARowThisDeviceNeverHadDoesNothing() {
        XCTAssertTrue(plan([], [task("a", at: 2, deleted: true)]).isEmpty)
    }

    // MARK: - First sync

    /// The guard that matters most in this file. A first sync against an empty or unreachable
    /// folder must not read "nothing" as the truth and wipe the board it was meant to protect.
    func testAdoptingNeverHappensAgainstAnEmptyFolder() {
        XCTAssertEqual(
            SyncBoardPlan.stance(hasSyncedBefore: false, remoteIsEmpty: true, adoptsOnFirstSync: true),
            .merge
        )
    }

    func testTheLosingDeviceAdoptsOnceAndMergesFromThenOn() {
        XCTAssertEqual(
            SyncBoardPlan.stance(hasSyncedBefore: false, remoteIsEmpty: false, adoptsOnFirstSync: true),
            .adopt
        )
        XCTAssertEqual(
            SyncBoardPlan.stance(hasSyncedBefore: true, remoteIsEmpty: false, adoptsOnFirstSync: true),
            .merge
        )
    }

    func testTheWinningDeviceAlwaysMerges() {
        XCTAssertEqual(
            SyncBoardPlan.stance(hasSyncedBefore: false, remoteIsEmpty: false, adoptsOnFirstSync: false),
            .merge
        )
    }

    // MARK: - Repairs

    /// Left alone, the blocked strip stays blocked forever by something nobody can see or finish.
    func testABlockerDeletedOnTheOtherDeviceStopsBlocking() {
        let blocker = task("b", "Blocker", at: 2, deleted: true)
        var blocked = task("a", at: 1)
        blocked.blockedBySyncID = "b"

        let repaired = SyncBoardPlan.clearDanglingBlockers([blocked, blocker])

        XCTAssertNil(repaired.first { $0.id == "a" }?.blockedBySyncID)
    }

    func testABlockerThatIsStillThereKeepsBlocking() {
        let blocker = task("b", "Blocker")
        var blocked = task("a", at: 1)
        blocked.blockedBySyncID = "b"

        let repaired = SyncBoardPlan.clearDanglingBlockers([blocked, blocker])

        XCTAssertEqual(repaired.first { $0.id == "a" }?.blockedBySyncID, "b")
    }

    func testAStripCannotBlockItself() {
        var looped = task("a", at: 1)
        looped.blockedBySyncID = "a"

        XCTAssertNil(SyncBoardPlan.clearSelfBlockers([looped]).first?.blockedBySyncID)
    }

    func testASketchDeletedOnTheOtherDeviceStopsBeingLinked() {
        var strip = task("a", at: 1)
        strip.linkedSketchSyncID = "k"
        let gone = SyncSketchRecord(id: "k", updatedAt: 2, isDeleted: true)

        XCTAssertNil(SyncBoardPlan.clearDanglingSketchLinks([strip], sketches: [gone]).first?.linkedSketchSyncID)
    }

    func testASketchThatIsStillThereStaysLinked() {
        var strip = task("a", at: 1)
        strip.linkedSketchSyncID = "k"
        let sketch = SyncSketchRecord(id: "k", updatedAt: 1)

        XCTAssertEqual(
            SyncBoardPlan.clearDanglingSketchLinks([strip], sketches: [sketch]).first?.linkedSketchSyncID,
            "k"
        )
    }

    func testRepairAppliesEveryRuleAtOnce() {
        var loopedAndLinked = task("a", at: 1)
        loopedAndLinked.blockedBySyncID = "a"
        loopedAndLinked.linkedSketchSyncID = "gone"
        var missingBlocker = task("b", at: 1)
        missingBlocker.blockedBySyncID = "missing"

        let repaired = SyncBoardPlan.repair([loopedAndLinked, missingBlocker], sketches: [])

        XCTAssertNil(repaired.first { $0.id == "a" }?.blockedBySyncID)
        XCTAssertNil(repaired.first { $0.id == "a" }?.linkedSketchSyncID)
        XCTAssertNil(repaired.first { $0.id == "b" }?.blockedBySyncID)
    }
}
