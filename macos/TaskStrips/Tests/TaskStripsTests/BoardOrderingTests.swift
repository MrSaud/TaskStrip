import SwiftData
import XCTest
@testable import TaskStrips

/// Drag-reorder has never been exercised by hand — `List.onMove` needs a real trackpad gesture,
/// which is exactly why the menu path exists. Both paths land in `BoardOrdering`, so the ordering
/// itself is checked here rather than by clicking.
final class BoardOrderingTests: XCTestCase {
    private var context: ModelContext!

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: TaskItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    /// Strips in board order, already numbered 0..<n the way the board keeps them.
    private func makeBoard(_ titles: [String]) -> [TaskItem] {
        let tasks = titles.enumerated().map { TaskItem(title: $0.element, orderIndex: $0.offset) }
        for task in tasks { context.insert(task) }
        return tasks
    }

    private func boardOrder(_ tasks: [TaskItem]) -> [String] {
        tasks.sorted { $0.orderIndex < $1.orderIndex }.map(\.title)
    }

    // MARK: - The drag path

    func testDragMoveRenumbersTheBoard() {
        let board = makeBoard(["A", "B", "C", "D"])
        BoardOrdering.move(from: IndexSet(integer: 0), to: 3, in: board)
        XCTAssertEqual(boardOrder(board), ["B", "C", "A", "D"])
    }

    // MARK: - The menu path

    func testMoveUpSwapsWithTheStripAbove() {
        let board = makeBoard(["A", "B", "C", "D"])
        XCTAssertTrue(BoardOrdering.move(board[2], .up, in: board))
        XCTAssertEqual(boardOrder(board), ["A", "C", "B", "D"])
    }

    func testMoveDownSwapsWithTheStripBelow() {
        let board = makeBoard(["A", "B", "C", "D"])
        XCTAssertTrue(BoardOrdering.move(board[1], .down, in: board))
        XCTAssertEqual(boardOrder(board), ["A", "C", "B", "D"])
    }

    func testMoveToTopKeepsEveryoneElseInOrder() {
        let board = makeBoard(["A", "B", "C", "D"])
        XCTAssertTrue(BoardOrdering.move(board[3], .top, in: board))
        XCTAssertEqual(boardOrder(board), ["D", "A", "B", "C"])
    }

    func testMoveToBottomKeepsEveryoneElseInOrder() {
        let board = makeBoard(["A", "B", "C", "D"])
        XCTAssertTrue(BoardOrdering.move(board[0], .bottom, in: board))
        XCTAssertEqual(boardOrder(board), ["B", "C", "D", "A"])
    }

    // MARK: - Edges

    func testTheTopStripCannotGoUpAndTheBottomOneCannotGoDown() {
        let board = makeBoard(["A", "B", "C"])
        for move in [BoardMove.up, .top] {
            XCTAssertFalse(BoardOrdering.canMove(board[0], move, in: board), "\(move) from the top")
            XCTAssertFalse(BoardOrdering.move(board[0], move, in: board))
        }
        for move in [BoardMove.down, .bottom] {
            XCTAssertFalse(BoardOrdering.canMove(board[2], move, in: board), "\(move) from the bottom")
            XCTAssertFalse(BoardOrdering.move(board[2], move, in: board))
        }
        XCTAssertEqual(boardOrder(board), ["A", "B", "C"], "a refused move must not disturb the board")
    }

    func testEveryOtherMoveIsOffered() {
        let board = makeBoard(["A", "B", "C"])
        for move in BoardMove.allCases {
            XCTAssertTrue(BoardOrdering.canMove(board[1], move, in: board), "\(move) from the middle")
        }
    }

    func testASingleStripBoardHasNowhereToGo() {
        let board = makeBoard(["Only"])
        for move in BoardMove.allCases {
            XCTAssertFalse(BoardOrdering.canMove(board[0], move, in: board), "\(move)")
        }
    }

    /// The menu is built from `filtered`, so it can be handed a strip that isn't on the visible
    /// board — an archived one, or one a filter dropped between render and click.
    func testAStripThatIsNotOnTheVisibleBoardIsLeftAlone() {
        let board = makeBoard(["A", "B"])
        let offBoard = TaskItem(title: "Archived", orderIndex: 99)
        context.insert(offBoard)

        XCTAssertFalse(BoardOrdering.canMove(offBoard, .top, in: board))
        XCTAssertFalse(BoardOrdering.move(offBoard, .top, in: board))
        XCTAssertEqual(boardOrder(board), ["A", "B"])
        XCTAssertEqual(offBoard.orderIndex, 99)
    }

    // MARK: - Renumbering

    /// `nextOrderIndex()` and the drag both assume the board's indices are 0..<n with no gaps.
    func testIndicesAreContiguousFromZeroAfterAMove() {
        let board = makeBoard(["A", "B", "C", "D", "E"])
        BoardOrdering.move(board[4], .top, in: board)
        XCTAssertEqual(board.map(\.orderIndex).sorted(), [0, 1, 2, 3, 4])
    }

    func testRenumberFlattensGappyIndices() {
        let board = makeBoard(["A", "B", "C"])
        board[0].orderIndex = 40
        board[1].orderIndex = 41
        board[2].orderIndex = 42

        BoardOrdering.renumber(board)
        XCTAssertEqual(board.map(\.orderIndex), [0, 1, 2])
    }
}
