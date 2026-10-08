import XCTest
@testable import ShiGuangCore

final class SwipeClassifierTests: XCTestCase {
    func testDirections() {
        XCTAssertEqual(SwipeClassifier.classify(translationX: 0, translationY: -120), .delete)
        XCTAssertEqual(SwipeClassifier.classify(translationX: 10, translationY: 130), .favorite)
        XCTAssertEqual(SwipeClassifier.classify(translationX: -150, translationY: 20), .next)
        XCTAssertEqual(SwipeClassifier.classify(translationX: 150, translationY: -20), .previous)
    }

    func testSmallDragIsIgnored() {
        XCTAssertEqual(SwipeClassifier.classify(translationX: 20, translationY: -30), .none)
        XCTAssertEqual(SwipeClassifier.classify(translationX: 0, translationY: 0), .none)
    }

    func testFlick() {
        XCTAssertEqual(SwipeClassifier.classify(translationX: 0, translationY: -40, predictedEndX: 0, predictedEndY: -400), .delete)
        XCTAssertEqual(SwipeClassifier.classify(translationX: -30, translationY: 0, predictedEndX: -500, predictedEndY: 0), .next)
    }

    func testPinch() {
        XCTAssertTrue(SwipeClassifier.shouldOpenDay(pinchScale: 0.6))
        XCTAssertFalse(SwipeClassifier.shouldOpenDay(pinchScale: 0.95))
        XCTAssertFalse(SwipeClassifier.shouldOpenDay(pinchScale: 1.4))
    }
}

final class CategoryTests: XCTestCase {
    func testCategoryRules() {
        let photo = MediaItem(id: "p")
        let video = MediaItem(id: "v", kind: .video)
        let shot = MediaItem(id: "s", isScreenshot: true)
        let gif = MediaItem(id: "g", isAnimated: true)
        let live = MediaItem(id: "l", isLivePhoto: true)
        let selfie = MediaItem(id: "f", isSelfie: true)
        let all = [photo, video, shot, gif, live, selfie]

        func ids(_ c: MediaCategory) -> Set<String> { Set(all.filter(c.contains).map(\.id)) }
        XCTAssertEqual(ids(.all).count, 6)
        XCTAssertEqual(ids(.photos), ["p", "l", "f"])
        XCTAssertEqual(ids(.videos), ["v"])
        XCTAssertEqual(ids(.screenshots), ["s"])
        XCTAssertEqual(ids(.animated), ["g"])
        XCTAssertEqual(ids(.livePhotos), ["l"])
        XCTAssertEqual(ids(.selfies), ["f"])
    }

    func testLongImage() {
        XCTAssertTrue(MediaItem(id: "x", pixelWidth: 1000, pixelHeight: 3000).isLongImage)
        XCTAssertFalse(MediaItem(id: "x", pixelWidth: 3000, pixelHeight: 4000).isLongImage)
        XCTAssertFalse(MediaItem(id: "x", kind: .video, pixelWidth: 1000, pixelHeight: 3000).isLongImage)
    }
}

final class UsageStatsTests: XCTestCase {
    let cal = TestSupport.calendar

    func testTotalsAndDaily() {
        var stats = UsageStats()
        let day = TestSupport.date(2026, 10, 8)
        stats.recordViewed(count: 15, at: day, calendar: cal)
        stats.recordDeleted(count: 3, bytes: 9_000_000, at: day, calendar: cal)
        stats.recordGroupCompleted()
        XCTAssertEqual(stats.totalViewed, 15)
        XCTAssertEqual(stats.totalDeleted, 3)
        XCTAssertEqual(stats.bytesFreed, 9_000_000)
        XCTAssertEqual(stats.groupsCompleted, 1)
        XCTAssertEqual(stats.stat(on: day, calendar: cal), DayStat(viewed: 15, deleted: 3, bytesFreed: 9_000_000))
        XCTAssertEqual(stats.deletionRate, 0.2, accuracy: 0.0001)
        XCTAssertEqual(stats.firstUseDate, day)
    }

    func testStreak() {
        var stats = UsageStats()
        for d in [3, 4, 5, 7] {
            stats.recordViewed(at: TestSupport.date(2026, 10, d), calendar: cal)
        }
        // 10/7 有、10/6 沒有 → 1
        XCTAssertEqual(stats.streak(asOf: TestSupport.date(2026, 10, 7), calendar: cal), 1)
        // 今天（10/8）還沒看，從昨天算起
        XCTAssertEqual(stats.streak(asOf: TestSupport.date(2026, 10, 8), calendar: cal), 1)
        XCTAssertEqual(stats.streak(asOf: TestSupport.date(2026, 10, 5), calendar: cal), 3)
        XCTAssertEqual(stats.streak(asOf: TestSupport.date(2026, 10, 10), calendar: cal), 0)
    }

    func testLastDays() {
        var stats = UsageStats()
        stats.recordViewed(count: 4, at: TestSupport.date(2026, 10, 6), calendar: cal)
        let days = stats.lastDays(3, asOf: TestSupport.date(2026, 10, 8), calendar: cal)
        XCTAssertEqual(days.map { DayBucket.key(for: $0.date, calendar: cal) }, ["2026-10-06", "2026-10-07", "2026-10-08"])
        XCTAssertEqual(days.map(\.stat.viewed), [4, 0, 0])
    }
}

final class SettingsTests: XCTestCase {
    func testClampAndDefaults() throws {
        var settings = AppSettings()
        settings.groupSize = 1000
        XCTAssertEqual(settings.groupSize, 100)
        settings.groupSize = 0
        XCTAssertEqual(settings.groupSize, 5)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"groupSize": 30, "category": "bogus"}"#.utf8))
        XCTAssertEqual(decoded.groupSize, 30)
        XCTAssertEqual(decoded.category, .all)
        XCTAssertTrue(decoded.hapticsEnabled)
        XCTAssertEqual(decoded.dateStyle, .full)
    }

    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.category = .screenshots
        settings.demoMode = true
        settings.reminderHour = 8
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }
}

final class FormattingTests: XCTestCase {
    let cal = TestSupport.calendar
    let now = TestSupport.date(2026, 10, 8)

    func testFullAndNumeric() {
        let date = TestSupport.date(2021, 3, 5)
        XCTAssertEqual(DateDisplay.format(date, style: .full, now: now, calendar: cal), "2021年3月5日 星期五")
        XCTAssertEqual(DateDisplay.format(date, style: .numeric, now: now, calendar: cal), "2021/03/05")
        XCTAssertEqual(DateDisplay.format(nil, style: .full, now: now, calendar: cal), "未知日期")
    }

    func testRelative() {
        func rel(_ y: Int, _ m: Int, _ d: Int) -> String {
            DateDisplay.format(TestSupport.date(y, m, d), style: .relative, now: now, calendar: cal)
        }
        XCTAssertEqual(rel(2026, 10, 8), "今天")
        XCTAssertEqual(rel(2026, 10, 7), "昨天")
        XCTAssertEqual(rel(2026, 10, 3), "5天前")
        XCTAssertEqual(rel(2026, 9, 20), "2周前")
        XCTAssertEqual(rel(2026, 6, 8), "4个月前")
        XCTAssertEqual(rel(2021, 10, 8), "5年前")
        XCTAssertEqual(rel(2026, 10, 9), "未来")
    }

    func testDayBucket() {
        let date = TestSupport.date(2026, 2, 3, 23)
        let range = DayBucket.range(containing: date, calendar: cal)
        XCTAssertEqual(range.start, TestSupport.date(2026, 2, 3, 0))
        XCTAssertEqual(range.duration, 86_400)
        XCTAssertEqual(DayBucket.key(for: date, calendar: cal), "2026-02-03")
        XCTAssertEqual(DayBucket.date(fromKey: "2026-02-03", calendar: cal), TestSupport.date(2026, 2, 3, 0))
        XCTAssertNil(DayBucket.date(fromKey: "bad", calendar: cal))
    }

    func testChronologicalSort() {
        let a = MediaItem(id: "a", creationDate: TestSupport.date(2026, 1, 2))
        let b = MediaItem(id: "b", creationDate: TestSupport.date(2026, 1, 1))
        let c = MediaItem(id: "c", creationDate: nil)
        XCTAssertEqual(DayBucket.sortedChronologically([c, a, b]).map(\.id), ["b", "a", "c"])
    }

    func testByteSizeAndDuration() {
        XCTAssertEqual(ByteSize.format(512), "512 B")
        XCTAssertEqual(ByteSize.format(1536), "1.5 KB")
        XCTAssertEqual(ByteSize.format(250 * 1024 * 1024), "250 MB")
        XCTAssertEqual(ByteSize.format(-5), "0 B")
        XCTAssertEqual(DurationText.format(7), "0:07")
        XCTAssertEqual(DurationText.format(750), "12:30")
        XCTAssertEqual(DurationText.format(3723), "1:02:03")
    }
}
