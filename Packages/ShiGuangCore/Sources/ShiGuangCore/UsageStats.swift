import Foundation

public struct DayStat: Codable, Equatable, Sendable {
    public var viewed: Int = 0
    public var deleted: Int = 0
    public var favorited: Int = 0
    public var bytesFreed: Int64 = 0

    public init(viewed: Int = 0, deleted: Int = 0, favorited: Int = 0, bytesFreed: Int64 = 0) {
        self.viewed = viewed
        self.deleted = deleted
        self.favorited = favorited
        self.bytesFreed = bytesFreed
    }
}

/// 統計頁的資料：只記「已瀏覽、已刪除」，不顯示還剩多少（done list 而非 todo list）。
public struct UsageStats: Codable, Equatable, Sendable {
    public private(set) var totalViewed: Int = 0
    public private(set) var totalDeleted: Int = 0
    public private(set) var totalFavorited: Int = 0
    public private(set) var groupsCompleted: Int = 0
    public private(set) var bytesFreed: Int64 = 0
    public private(set) var firstUseDate: Date?
    /// "yyyy-MM-dd" → 當天統計
    public private(set) var daily: [String: DayStat] = [:]

    public init() {}

    private mutating func update(_ date: Date, calendar: Calendar, _ change: (inout DayStat) -> Void) {
        if firstUseDate == nil || date < firstUseDate! { firstUseDate = date }
        let key = DayBucket.key(for: date, calendar: calendar)
        var stat = daily[key] ?? DayStat()
        change(&stat)
        daily[key] = stat
    }

    public mutating func recordViewed(count: Int = 1, at date: Date, calendar: Calendar) {
        guard count > 0 else { return }
        totalViewed += count
        update(date, calendar: calendar) { $0.viewed += count }
    }

    public mutating func recordDeleted(count: Int, bytes: Int64, at date: Date, calendar: Calendar) {
        guard count > 0 else { return }
        totalDeleted += count
        bytesFreed += max(bytes, 0)
        update(date, calendar: calendar) {
            $0.deleted += count
            $0.bytesFreed += max(bytes, 0)
        }
    }

    public mutating func recordFavorited(count: Int = 1, at date: Date, calendar: Calendar) {
        totalFavorited = max(totalFavorited + count, 0)
        update(date, calendar: calendar) { $0.favorited = max($0.favorited + count, 0) }
    }

    public mutating func recordGroupCompleted() {
        groupsCompleted += 1
    }

    public func stat(on date: Date, calendar: Calendar) -> DayStat {
        daily[DayBucket.key(for: date, calendar: calendar)] ?? DayStat()
    }

    /// 連續回顧天數：今天（或昨天，今天還沒看也不算中斷）往前連續有瀏覽的天數。
    public func streak(asOf now: Date, calendar: Calendar) -> Int {
        var day = calendar.startOfDay(for: now)
        if stat(on: day, calendar: calendar).viewed == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while stat(on: day, calendar: calendar).viewed > 0 {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    /// 最近 n 天（由舊到新），供統計圖表使用。
    public func lastDays(_ n: Int, asOf now: Date, calendar: Calendar) -> [(date: Date, stat: DayStat)] {
        guard n > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<n).reversed().compactMap { offset -> (date: Date, stat: DayStat)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date, stat(on: date, calendar: calendar))
        }
    }

    /// 刪除率，0...1
    public var deletionRate: Double {
        totalViewed == 0 ? 0 : min(Double(totalDeleted) / Double(totalViewed), 1)
    }
}
