import XCTest
@testable import ShiGuangCore

final class ViewHistoryTests: XCTestCase {
    let t0 = TestSupport.date(2026, 1, 1)

    func testMarkViewedKeepsLatestDate() {
        var history = ViewHistory()
        history.markViewed("x", at: t0.addingTimeInterval(100))
        history.markViewed("x", at: t0)
        XCTAssertEqual(history.lastViewed("x"), t0.addingTimeInterval(100))
    }

    func testRepeatWindow() {
        var history = ViewHistory()
        history.markViewed("x", at: t0)
        XCTAssertTrue(history.hasViewed("x", now: t0.addingTimeInterval(2 * 365 * 86_400)))
        XCTAssertFalse(history.hasViewed("x", now: t0.addingTimeInterval(3 * 365 * 86_400 + 1)))
        XCTAssertFalse(history.hasViewed("y", now: t0))
    }

    func testResetSpecificIDs() {
        var history = ViewHistory()
        history.markViewed("a", at: t0)
        history.markViewed("b", at: t0)
        history.reset(ids: ["a"], at: t0.addingTimeInterval(10))
        XCTAssertNil(history.lastViewed("a"))
        XCTAssertNotNil(history.lastViewed("b"))
    }

    func testPrune() {
        var history = ViewHistory()
        history.markViewed("a", at: t0)
        history.markViewed("b", at: t0)
        history.prune(keeping: ["b"])
        XCTAssertEqual(history.viewedCount, 1)
        XCTAssertNil(history.lastViewed("a"))
    }

    func testMergeUnionsAndTakesLatest() {
        var local = ViewHistory()
        local.markViewed("a", at: t0)
        local.markViewed("b", at: t0)
        var remote = ViewHistory()
        remote.markViewed("b", at: t0.addingTimeInterval(50))
        remote.markViewed("c", at: t0)
        let merged = local.merged(with: remote)
        XCTAssertEqual(merged.viewedCount, 3)
        XCTAssertEqual(merged.lastViewed("b"), t0.addingTimeInterval(50))
    }

    func testMergeHonorsRemoteReset() {
        var local = ViewHistory()
        local.markViewed("a", at: t0)
        local.markViewed("b", at: t0.addingTimeInterval(200))
        var remote = local
        remote.reset(ids: ["a", "b"], at: t0.addingTimeInterval(100))
        let merged = local.merged(with: remote)
        // a 的瀏覽早於重置，被清除；b 在重置之後又看過，保留
        XCTAssertNil(merged.lastViewed("a"))
        XCTAssertEqual(merged.lastViewed("b"), t0.addingTimeInterval(200))
    }

    func testMergeHonorsResetAll() {
        var local = ViewHistory()
        local.markViewed("a", at: t0)
        var remote = ViewHistory()
        remote.resetAll(at: t0.addingTimeInterval(10))
        remote.markViewed("c", at: t0.addingTimeInterval(20))
        let merged = local.merged(with: remote)
        XCTAssertNil(merged.lastViewed("a"))
        XCTAssertNotNil(merged.lastViewed("c"))
        XCTAssertEqual(merged.resetAllAt, t0.addingTimeInterval(10))
        // 合併是對稱的
        XCTAssertEqual(merged, remote.merged(with: local))
    }

    func testCodableRoundTrip() throws {
        var history = ViewHistory()
        history.markViewed("a", at: t0)
        history.reset(ids: ["z"], at: t0)
        let data = try JSONEncoder().encode(history)
        XCTAssertEqual(try JSONDecoder().decode(ViewHistory.self, from: data), history)
    }
}
