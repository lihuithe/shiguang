import XCTest
@testable import ShiGuangCore

final class GroupSessionTests: XCTestCase {
    func testDeleteRemovesItemAndNextSlidesIn() {
        var session = GroupSession(items: TestSupport.items(3))
        XCTAssertEqual(session.current?.id, "a0")
        XCTAssertNil(session.previous)
        XCTAssertEqual(session.next?.id, "a1")

        XCTAssertEqual(session.deleteCurrent()?.id, "a0")
        XCTAssertEqual(session.current?.id, "a1")
        XCTAssertEqual(session.visibleItems.map(\.id), ["a1", "a2"])
        XCTAssertNil(session.previous)
        XCTAssertEqual(session.pendingDeletion.map(\.id), ["a0"])
    }

    func testDeletingLastItemFinishesGroup() {
        var session = GroupSession(items: TestSupport.items(2))
        session.goForward()
        session.deleteCurrent()
        XCTAssertTrue(session.isFinished)
        XCTAssertNil(session.current)
        XCTAssertEqual(session.pendingDeletion.map(\.id), ["a1"])
    }

    func testForwardPastLastFinishes() {
        var session = GroupSession(items: TestSupport.items(2))
        session.goForward()
        XCTAssertFalse(session.isFinished)
        session.goForward()
        XCTAssertTrue(session.isFinished)
        session.goForward()
        XCTAssertEqual(session.currentIndex, 2)
    }

    func testGoBack() {
        var session = GroupSession(items: TestSupport.items(3))
        session.goBack()
        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertFalse(session.canUndo)
        session.goForward()
        session.goForward()
        session.goBack()
        XCTAssertEqual(session.current?.id, "a1")
    }

    func testUndoDeleteRestoresAtSamePosition() {
        var session = GroupSession(items: TestSupport.items(4))
        session.goForward()
        session.deleteCurrent()
        XCTAssertEqual(session.current?.id, "a2")

        XCTAssertEqual(session.undo(), .deleted(id: "a1", visibleIndex: 1))
        XCTAssertEqual(session.current?.id, "a1")
        XCTAssertTrue(session.pendingDeletion.isEmpty)
        XCTAssertEqual(session.visibleItems.count, 4)

        // 翻頁不進撤銷記錄
        XCTAssertNil(session.undo())
        XCTAssertEqual(session.current?.id, "a1")
    }

    func testMoveToVisibleIndex() {
        var session = GroupSession(items: TestSupport.items(3))
        session.move(toVisibleIndex: 2)
        XCTAssertEqual(session.current?.id, "a2")
        session.move(toVisibleIndex: 99)
        XCTAssertTrue(session.isFinished)
        session.move(toVisibleIndex: -3)
        XCTAssertEqual(session.current?.id, "a0")
        XCTAssertFalse(session.canUndo)
    }

    func testUndoAfterFinishingReturnsToLastItem() {
        var session = GroupSession(items: TestSupport.items(2))
        session.goForward()
        session.deleteCurrent()
        XCTAssertTrue(session.isFinished)
        session.undo()
        XCTAssertFalse(session.isFinished)
        XCTAssertEqual(session.current?.id, "a1")
    }

    func testFavoriteToggleAndUndo() {
        var items = TestSupport.items(2)
        items[1].isFavorite = true
        var session = GroupSession(items: items)
        XCTAssertTrue(session.isFavorite("a1"))
        XCTAssertTrue(session.toggleFavorite("a0"))
        XCTAssertEqual(session.undo(), .favoriteChanged(id: "a0", wasFavorite: false))
        XCTAssertFalse(session.isFavorite("a0"))
        XCTAssertFalse(session.toggleFavorite("unknown"))
    }

    func testKeepAndReopen() {
        var session = GroupSession(items: TestSupport.items(3))
        session.deleteCurrent()
        session.goForward()
        session.goForward()
        XCTAssertTrue(session.isFinished)

        session.keep("a0")
        XCTAssertTrue(session.pendingDeletion.isEmpty)
        XCTAssertEqual(session.currentIndex, 2)

        session.reopen()
        XCTAssertEqual(session.current?.id, "a2")
    }

    func testRemoveExternallyKeepsPositionAndMarks() {
        var session = GroupSession(items: TestSupport.items(5))
        session.deleteCurrent()          // a0 待刪除
        session.goForward()              // 目前 a2
        XCTAssertEqual(session.current?.id, "a2")

        session.removeExternally(["a1", "zzz"])
        XCTAssertEqual(session.items.map(\.id), ["a0", "a2", "a3", "a4"])
        XCTAssertEqual(session.current?.id, "a2")
        XCTAssertEqual(session.pendingDeletion.map(\.id), ["a0"])
        XCTAssertFalse(session.canUndo)

        // 刪掉目前這張：停在原位置的下一張
        session.removeExternally(["a2"])
        XCTAssertEqual(session.current?.id, "a3")

        // 刪掉待刪除的那張：標記一併移除
        session.removeExternally(["a0"])
        XCTAssertTrue(session.pendingDeletion.isEmpty)
        XCTAssertEqual(session.current?.id, "a3")

        session.removeExternally(["a3", "a4"])
        XCTAssertTrue(session.isEmpty)
        XCTAssertTrue(session.isFinished)
    }

    func testUpcomingProgressAndRemaining() {
        var session = GroupSession(items: TestSupport.items(5))
        XCTAssertEqual(session.upcoming(3).map(\.id), ["a0", "a1", "a2"])
        XCTAssertEqual(session.progress, 0.2, accuracy: 0.0001)
        XCTAssertEqual(session.remainingCount, 4)

        session.deleteCurrent()
        // a1 是原組的第 2 張
        XCTAssertEqual(session.progress, 0.4, accuracy: 0.0001)
        XCTAssertEqual(session.remainingCount, 3)

        for _ in 0..<4 { session.goForward() }
        XCTAssertEqual(session.progress, 1)
        XCTAssertTrue(session.upcoming(3).isEmpty)
    }
}
