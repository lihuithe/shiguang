import Foundation

/// 統計頁按「照片 / 截屏 / 視頻」分開計數。
public enum StatsBucket: String, Codable, CaseIterable, Sendable, Identifiable {
    case photo
    case screenshot
    case video

    public var id: String { rawValue }

    public init(item: MediaItem) {
        if item.kind == .video {
            self = .video
        } else if item.isScreenshot {
            self = .screenshot
        } else {
            self = .photo
        }
    }

    public var title: String {
        switch self {
        case .photo: return "照片"
        case .screenshot: return "截屏"
        case .video: return "视频"
        }
    }

    public var systemImage: String {
        switch self {
        case .photo: return "photo"
        case .screenshot: return "camera.viewfinder"
        case .video: return "play.rectangle"
        }
    }
}

public struct BucketStat: Codable, Equatable, Sendable {
    public var viewed: Int = 0
    public var deleted: Int = 0
    public var bytesFreed: Int64 = 0

    public init(viewed: Int = 0, deleted: Int = 0, bytesFreed: Int64 = 0) {
        self.viewed = viewed
        self.deleted = deleted
        self.bytesFreed = bytesFreed
    }
}

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

/// 統計頁的資料：只記「已瀏覽、已刪除、騰出空間」，不顯示還剩多少。
public struct UsageStats: Codable, Equatable, Sendable {
    public private(set) var totalViewed: Int = 0
    public private(set) var totalDeleted: Int = 0
    public private(set) var totalFavorited: Int = 0
    public private(set) var groupsCompleted: Int = 0
    public private(set) var bytesFreed: Int64 = 0
    public private(set) var firstUseDate: Date?
    /// StatsBucket.rawValue → 該類統計
    public private(set) var buckets: [String: BucketStat] = [:]
    /// "yyyy-MM-dd" → 當天統計
    public private(set) var daily: [String: DayStat] = [:]

    public init() {}

    public func stat(for bucket: StatsBucket) -> BucketStat {
        buckets[bucket.rawValue] ?? BucketStat()
    }

    /// 各類騰出空間佔總量的比例，總量為 0 時都是 0
    public func freedShare(of bucket: StatsBucket) -> Double {
        guard bytesFreed > 0 else { return 0 }
        return Double(stat(for: bucket).bytesFreed) / Double(bytesFreed)
    }

    private mutating func update(_ date: Date, calendar: Calendar, _ change: (inout DayStat) -> Void) {
        if firstUseDate == nil || date < firstUseDate! { firstUseDate = date }
        let key = DayBucket.key(for: date, calendar: calendar)
        var stat = daily[key] ?? DayStat()
        change(&stat)
        daily[key] = stat
    }

    private mutating func updateBucket(_ bucket: StatsBucket, _ change: (inout BucketStat) -> Void) {
        var stat = buckets[bucket.rawValue] ?? BucketStat()
        change(&stat)
        buckets[bucket.rawValue] = stat
    }

    public mutating func recordViewed(_ bucket: StatsBucket, count: Int = 1, at date: Date, calendar: Calendar) {
        guard count > 0 else { return }
        totalViewed += count
        updateBucket(bucket) { $0.viewed += count }
        update(date, calendar: calendar) { $0.viewed += count }
    }

    public mutating func recordDeleted(_ bucket: StatsBucket, count: Int, bytes: Int64, at date: Date, calendar: Calendar) {
        guard count > 0 else { return }
        let bytes = max(bytes, 0)
        totalDeleted += count
        bytesFreed += bytes
        updateBucket(bucket) {
            $0.deleted += count
            $0.bytesFreed += bytes
        }
        update(date, calendar: calendar) {
            $0.deleted += count
            $0.bytesFreed += bytes
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

    /// 最近 n 天（由舊到新）。
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

    // 舊版本的檔案沒有 buckets 等欄位，缺少時用預設值
    enum CodingKeys: String, CodingKey {
        case totalViewed, totalDeleted, totalFavorited, groupsCompleted, bytesFreed, firstUseDate, buckets, daily
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalViewed = try c.decodeIfPresent(Int.self, forKey: .totalViewed) ?? 0
        totalDeleted = try c.decodeIfPresent(Int.self, forKey: .totalDeleted) ?? 0
        totalFavorited = try c.decodeIfPresent(Int.self, forKey: .totalFavorited) ?? 0
        groupsCompleted = try c.decodeIfPresent(Int.self, forKey: .groupsCompleted) ?? 0
        bytesFreed = try c.decodeIfPresent(Int64.self, forKey: .bytesFreed) ?? 0
        firstUseDate = try c.decodeIfPresent(Date.self, forKey: .firstUseDate)
        buckets = try c.decodeIfPresent([String: BucketStat].self, forKey: .buckets) ?? [:]
        daily = try c.decodeIfPresent([String: DayStat].self, forKey: .daily) ?? [:]
    }
}
