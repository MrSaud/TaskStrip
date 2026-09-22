import SwiftData
import XCTest
@testable import TaskStrips

final class SyncNoteFoldTests: XCTestCase {
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
        suite = "SyncNoteFoldTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testTheSyncNoteBecomesAQuickNoteOnce() throws {
        context.insert(SyncNote(syncID: "main", text: "  Groceries: milk, eggs  "))
        XCTAssertEqual(SyncNoteFold.run(in: context, defaults: defaults), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).map(\.text), ["Groceries: milk, eggs"])

        // Never twice, even if it's run again.
        XCTAssertEqual(SyncNoteFold.run(in: context, defaults: defaults), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Note>()), 1)
    }

    func testAnEmptySyncNoteAddsNothing() throws {
        context.insert(SyncNote(syncID: "main", text: "   "))
        XCTAssertEqual(SyncNoteFold.run(in: context, defaults: defaults), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Note>()), 0)
    }

    func testTextAlreadyInANoteIsNotAddedAgain() throws {
        context.insert(Note(text: "Same"))
        context.insert(SyncNote(syncID: "main", text: "Same"))
        XCTAssertEqual(SyncNoteFold.run(in: context, defaults: defaults), 0)
    }
}
