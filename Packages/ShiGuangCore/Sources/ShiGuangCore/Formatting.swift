import Foundation

/// 照片日期與容量的中文格式化。手寫而不依賴 DateFormatter 的語系資料，結果在各平台一致、可測試。
public enum DateDisplay {
    private static let weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]

    public static func format(_ date: Date?, style: DateDisplayStyle, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "未知日期" }
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let year = c.year ?? 0, month = c.month ?? 0, day = c.day ?? 0
        switch style {
        case .full:
            let weekday = c.weekday.map { weekdays[($0 - 1 + 7) % 7] } ?? ""
            return "\(year)年\(month)月\(day)日 \(weekday)"
        case .numeric:
            return String(format: "%04d/%02d/%02d", year, month, day)
        case .relative:
            return relative(date, now: now, calendar: calendar)
        }
    }

    public static func relative(_ date: Date, now: Date, calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        if days < 0 { return "未来" }
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 7 { return "\(days)天前" }
        if days < 30 { return "\(days / 7)周前" }
        let months = calendar.dateComponents([.month], from: start, to: today).month ?? 0
        if months < 12 { return "\(max(months, 1))个月前" }
        let years = calendar.dateComponents([.year], from: start, to: today).year ?? 0
        return "\(max(years, 1))年前"
    }

    /// 「回到那天」的標題，例如「2021年3月5日 · 4年前的今天」。
    public static func dayTitle(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let full = format(date, style: .full, now: now, calendar: calendar)
        return "\(full) · \(relative(date, now: now, calendar: calendar))"
    }
}

public enum ByteSize {
    public static func format(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(max(bytes, 0))
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == 0 { return "\(Int(value)) 字节" }
        let number = String(format: value >= 100 ? "%.0f" : "%.1f", value)
        return "\(number) \(units[unit])"
    }
}

public enum DurationText {
    /// 影片長度，例如 0:07、12:30、1:02:03
    public static func format(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
