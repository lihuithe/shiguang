import Foundation

/// 瀏覽記錄：記住每個媒體最後一次被看到的時間，讓看過的內容在一段時間內不再被抽到。
///
/// 為了支援 iCloud 多裝置同步，重置操作用「墓碑」記錄，合併時以時間較新者為準（LWW）。
public struct ViewHistory: Codable, Equatable, Sendable {
    /// 看過的內容預設 3 年內不再出現。
    public static let defaultRepeatWindow: TimeInterval = 3 * 365 * 24 * 60 * 60

    /// assetID → 最後瀏覽時間
    public private(set) var records: [String: Date]
    /// assetID → 被重置的時間；只有晚於此時間的瀏覽才有效
    public private(set) var tombstones: [String: Date]
    /// 全部重置的時間；早於此時間的瀏覽一律失效
    public private(set) var resetAllAt: Date?

    public init(records: [String: Date] = [:], tombstones: [String: Date] = [:], resetAllAt: Date? = nil) {
        self.records = records
        self.tombstones = tombstones
        self.resetAllAt = resetAllAt
    }

    public var viewedCount: Int { records.count }

    public mutating func markViewed(_ id: String, at date: Date) {
        if let existing = records[id], existing >= date { return }
        records[id] = date
    }

    public func lastViewed(_ id: String) -> Date? {
        records[id]
    }

    public func hasViewed(_ id: String, now: Date, window: TimeInterval = ViewHistory.defaultRepeatWindow) -> Bool {
        guard let date = records[id] else { return false }
        return now.timeIntervalSince(date) < window
    }

    /// 重置指定媒體的瀏覽記錄（例如「重置截图浏览记录」）。
    public mutating func reset<S: Sequence>(ids: S, at date: Date) where S.Element == String {
        for id in ids {
            records[id] = nil
            tombstones[id] = max(tombstones[id] ?? .distantPast, date)
        }
    }

    public mutating func resetAll(at date: Date) {
        records.removeAll()
        tombstones.removeAll()
        resetAllAt = max(resetAllAt ?? .distantPast, date)
    }

    /// 移除已不存在於相簿中的媒體（例如已刪除），避免記錄無限成長。
    public mutating func prune(keeping existing: Set<String>) {
        records = records.filter { existing.contains($0.key) }
        tombstones = tombstones.filter { existing.contains($0.key) }
    }

    /// 合併另一台裝置的記錄。
    public func merged(with other: ViewHistory) -> ViewHistory {
        let resetAll: Date? = [resetAllAt, other.resetAllAt].compactMap { $0 }.max()

        var tombs = tombstones
        for (id, date) in other.tombstones {
            tombs[id] = max(tombs[id] ?? .distantPast, date)
        }

        var merged: [String: Date] = records
        for (id, date) in other.records {
            merged[id] = max(merged[id] ?? .distantPast, date)
        }

        merged = merged.filter { id, viewedAt in
            if let resetAll, viewedAt <= resetAll { return false }
            if let tomb = tombs[id], viewedAt <= tomb { return false }
            return true
        }
        if let resetAll {
            tombs = tombs.filter { $0.value > resetAll }
        }
        return ViewHistory(records: merged, tombstones: tombs, resetAllAt: resetAll)
    }
}
