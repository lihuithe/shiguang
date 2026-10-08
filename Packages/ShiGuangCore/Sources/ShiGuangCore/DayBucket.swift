import Foundation

/// 「回到那天」與統計共用的日期分桶工具。
public enum DayBucket {
    public static func range(containing date: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// 例如 "2026-10-08"，用作統計的字典鍵。
    public static func key(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func date(fromKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// 把媒體依拍攝時間排序，供「回到那天」的時間線使用；沒有日期的放最後。
    public static func sortedChronologically(_ items: [MediaItem]) -> [MediaItem] {
        items.sorted { a, b in
            switch (a.creationDate, b.creationDate) {
            case let (x?, y?): return x == y ? a.id < b.id : x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.id < b.id
            }
        }
    }
}
