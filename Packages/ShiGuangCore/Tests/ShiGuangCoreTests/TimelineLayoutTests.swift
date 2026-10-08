import XCTest
@testable import ShiGuangCore

final class TimelineLayoutTests: XCTestCase {
    private func item(_ id: String, _ w: Int, _ h: Int) -> MediaItem {
        MediaItem(id: id, pixelWidth: w, pixelHeight: h)
    }

    func testMasonryFillsShortestRow() {
        // 寬 150、寬 75、寬 100、寬 100（行高 100，間距 0）
        let items = [item("a", 1500, 1000), item("b", 750, 1000), item("c", 1000, 1000), item("d", 1000, 1000)]
        let layout = TimelineLayout(items: items, rows: 2, rowHeight: 100, spacing: 0)
        XCTAssertEqual(layout.frames.map(\.row), [0, 1, 1, 0])
        XCTAssertEqual(layout.frames.map(\.x), [0, 0, 75, 150])
        XCTAssertEqual(layout.contentWidth, 250)
    }

    func testSpacingAndAspectClamp() {
        let items = [item("tall", 100, 1000), item("wide", 4000, 1000)]
        let layout = TimelineLayout(items: items, rows: 1, rowHeight: 100, spacing: 4)
        XCTAssertEqual(layout.frames[0].width, 55)
        XCTAssertEqual(layout.frames[1].x, 59)
        XCTAssertEqual(layout.frames[1].width, 180)
        XCTAssertEqual(layout.contentWidth, 239)
        XCTAssertEqual(TimelineLayout.aspect(of: MediaItem(id: "x")), 0.75)
    }

    func testNearestAndCentering() {
        let items = (0..<10).map { item("i\($0)", 1000, 1000) }
        let layout = TimelineLayout(items: items, rows: 1, rowHeight: 100, spacing: 0)
        XCTAssertEqual(layout.index(nearestX: 420), 4)
        XCTAssertEqual(layout.offset(centering: 5, viewportWidth: 300), 400)
        XCTAssertEqual(layout.offset(centering: 0, viewportWidth: 300), 0)
        XCTAssertEqual(layout.offset(centering: 9, viewportWidth: 300), 700)
        XCTAssertNil(TimelineLayout(items: [], rows: 2, rowHeight: 100, spacing: 0).index(nearestX: 0))
    }

    func testLowerBound() {
        let dates: [Date?] = [nil, Date(timeIntervalSince1970: 10), Date(timeIntervalSince1970: 20), Date(timeIntervalSince1970: 20), Date(timeIntervalSince1970: 30)]
        func search(_ t: TimeInterval) -> Int {
            TimelineSearch.lowerBound(count: dates.count, target: Date(timeIntervalSince1970: t)) { dates[$0] }
        }
        XCTAssertEqual(search(5), 1)
        XCTAssertEqual(search(20), 2)
        XCTAssertEqual(search(25), 4)
        XCTAssertEqual(search(99), 5)
    }

    func testWindow() {
        XCTAssertEqual(TimelineSearch.window(around: 5, radius: 2, count: 100), 3..<8)
        XCTAssertEqual(TimelineSearch.window(around: 1, radius: 3, count: 100), 0..<5)
        XCTAssertEqual(TimelineSearch.window(around: 120, radius: 3, count: 100), 96..<100)
        XCTAssertEqual(TimelineSearch.window(around: 0, radius: 3, count: 0), 0..<0)
    }
}
