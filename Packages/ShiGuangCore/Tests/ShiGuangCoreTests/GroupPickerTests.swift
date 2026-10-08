import XCTest
@testable import ShiGuangCore

final class GroupPickerTests: XCTestCase {
    let now = TestSupport.date(2026, 10, 8)

    func testPicksRequestedSizeWithoutDuplicates() {
        let source = ArrayMediaSource(TestSupport.items(1000))
        var rng = SeededRandomNumberGenerator(seed: 1)
        let result = GroupPicker.pick(from: source, history: ViewHistory(), size: 15, now: now, using: &rng)
        XCTAssertEqual(result.items.count, 15)
        XCTAssertEqual(Set(result.items.map(\.id)).count, 15)
        XCTAssertFalse(result.didRecycle)
    }

    func testSmallLibraryReturnsEverything() {
        let source = ArrayMediaSource(TestSupport.items(4))
        var rng = SeededRandomNumberGenerator(seed: 2)
        let result = GroupPicker.pick(from: source, history: ViewHistory(), size: 15, now: now, using: &rng)
        XCTAssertEqual(Set(result.items.map(\.id)), ["a0", "a1", "a2", "a3"])
    }

    func testEmptyLibrary() {
        var rng = SeededRandomNumberGenerator(seed: 3)
        let result = GroupPicker.pick(from: ArrayMediaSource([]), history: ViewHistory(), size: 15, now: now, using: &rng)
        XCTAssertTrue(result.items.isEmpty)
    }

    func testSkipsViewedItems() {
        let items = TestSupport.items(100)
        var history = ViewHistory()
        for item in items.prefix(90) {
            history.markViewed(item.id, at: now.addingTimeInterval(-3600))
        }
        var rng = SeededRandomNumberGenerator(seed: 4)
        let result = GroupPicker.pick(from: ArrayMediaSource(items), history: history, size: 10, now: now, using: &rng)
        XCTAssertEqual(Set(result.items.map(\.id)), Set(items.suffix(10).map(\.id)))
        XCTAssertFalse(result.didRecycle)
    }

    func testConsecutiveGroupsNeverRepeatUntilExhausted() {
        let items = TestSupport.items(60)
        var history = ViewHistory()
        var rng = SeededRandomNumberGenerator(seed: 5)
        var seen = Set<String>()
        for round in 0..<4 {
            let result = GroupPicker.pick(from: ArrayMediaSource(items), history: history, size: 15, now: now, using: &rng)
            XCTAssertEqual(result.items.count, 15)
            XCTAssertFalse(result.didRecycle, "round \(round)")
            for item in result.items {
                XCTAssertFalse(seen.contains(item.id), "\(item.id) repeated in round \(round)")
                seen.insert(item.id)
                history.markViewed(item.id, at: now)
            }
        }
        XCTAssertEqual(seen.count, 60)
    }

    func testRecyclesOldestViewedWhenExhausted() {
        let items = TestSupport.items(5)
        var history = ViewHistory()
        for (offset, item) in items.enumerated() {
            history.markViewed(item.id, at: now.addingTimeInterval(TimeInterval(-1000 + offset)))
        }
        var rng = SeededRandomNumberGenerator(seed: 6)
        let result = GroupPicker.pick(from: ArrayMediaSource(items), history: history, size: 2, now: now, using: &rng)
        XCTAssertTrue(result.didRecycle)
        XCTAssertEqual(Set(result.items.map(\.id)), ["a0", "a1"])
    }

    func testViewsOlderThanWindowCountAsUnviewed() {
        let items = TestSupport.items(3)
        var history = ViewHistory()
        let fourYearsAgo = now.addingTimeInterval(-4 * 365 * 86_400)
        for item in items { history.markViewed(item.id, at: fourYearsAgo) }
        var rng = SeededRandomNumberGenerator(seed: 7)
        let result = GroupPicker.pick(from: ArrayMediaSource(items), history: history, size: 3, now: now, using: &rng)
        XCTAssertFalse(result.didRecycle)
        XCTAssertEqual(result.items.count, 3)
    }

    func testExcludedIDsAreNeverPicked() {
        let items = TestSupport.items(20)
        let excluded: Set<String> = Set(items.prefix(18).map(\.id))
        var rng = SeededRandomNumberGenerator(seed: 8)
        let result = GroupPicker.pick(from: ArrayMediaSource(items), history: ViewHistory(), size: 15, now: now, excluding: excluded, using: &rng)
        XCTAssertEqual(Set(result.items.map(\.id)), ["a18", "a19"])
    }

    func testSeededGeneratorIsDeterministic() {
        var a = SeededRandomNumberGenerator(seed: 42)
        var b = SeededRandomNumberGenerator(seed: 42)
        XCTAssertEqual((0..<5).map { _ in a.next() }, (0..<5).map { _ in b.next() })
    }

    func testDemoLibraryIsReproducibleAndCoversCategories() {
        let first = DemoLibrary.items(count: 240, now: now)
        let second = DemoLibrary.items(count: 240, now: now)
        XCTAssertEqual(first, second)
        for category in MediaCategory.allCases {
            XCTAssertFalse(first.filter(category.contains).isEmpty, "\(category) empty")
        }
        XCTAssertTrue(first.allSatisfy { ($0.creationDate ?? .distantFuture) <= now })
        XCTAssertTrue(first.allSatisfy { DemoLibrary.isDemoID($0.id) })
    }
}
