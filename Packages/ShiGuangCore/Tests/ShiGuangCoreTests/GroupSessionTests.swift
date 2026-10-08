import XCTest
@testable import ShiGuangCore

final class GroupSessionTests: XCTestCase {
    func testSwipeFlowAndPendingDeletion() {
        var session = GroupSession(items: TestSupport.items(3))
        XCTAssertEqual(session.current?.id, "a0")
        XCTAssertEqual(session.progressText, "1/3")

        session.markCurrentForDeletion()
        XCTAssertEqual(session.current?.id, "a1")
        session.next()
        session.markCurrentForDeletion()

        XCTAssertTrue(session.isFinished)
        XCTAssertNil(session.current)
        XCTAssertEqual(session.progressText, "3/3")
        XCTAssertEqual(session.pendingDeletion.map(\.id), ["a0", "a2"])
    }

    func testPreviousAndBounds() {
        var session = GroupSession(items: TestSupport.items(2))
        session.previous()
        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertFalse(session.canUndo)
        session.next()
        session.previous()
        XCTAssertEqual(session.currentIndex, 0)
        session.next()
        session.next()
        session.next()
        XCTAssertEqual(session.currentIndex, 2)
    }

    func testUndoRestoresDeletionAndPosition() {
        var session = GroupSession(items: TestSupport.items(3))
        session.next()
        session.markCurrentForDeletion()
        XCTAssertEqual(session.currentIndex, 2)

        let event = session.undo()
        XCTAssertEqual(event, .markedForDeletion(id: "a1", fromIndex: 1))
        XCTAssertEqual(session.currentIndex, 1)
        XCTAssertTrue(session.pendingDeletion.isEmpty)

        session.undo()
        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertNil(session.undo())
    }

    func testFavoriteToggleAndUndo() {
        var items = TestSupport.items(2)
        items[1].isFavorite = true
        var session = GroupSession(items: items)
        XCTAssertTrue(session.isFavorite("a1"))
        XCTAssertTrue(session.toggleFavorite("a0"))
        XCTAssertTrue(session.isFavorite("a0"))
        XCTAssertEqual(session.undo(), .favoriteChanged(id: "a0", wasFavorite: false))
        XCTAssertFalse(session.isFavorite("a0"))
        XCTAssertFalse(session.toggleFavorite("unknown"))
    }

    func testToggleDeletionInReview() {
        var session = GroupSession(items: TestSupport.items(2))
        session.markCurrentForDeletion()
        session.finish()
        session.toggleDeletion("a0")
        XCTAssertTrue(session.pendingDeletion.isEmpty)
        session.toggleDeletion("a1")
        XCTAssertEqual(session.pendingDeletion.map(\.id), ["a1"])
        session.undo()
        XCTAssertTrue(session.pendingDeletion.isEmpty)
        XCTAssertTrue(session.isFinished)
    }

    func testJump() {
        var session = GroupSession(items: TestSupport.items(5))
        session.finish()
        session.jump(to: 2)
        XCTAssertEqual(session.current?.id, "a2")
        session.jump(to: 99)
        XCTAssertEqual(session.currentIndex, 2)
    }
}
