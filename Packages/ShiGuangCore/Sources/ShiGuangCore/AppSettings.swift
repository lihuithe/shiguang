import Foundation

public enum DateDisplayStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// 2021年3月5日 星期五
    case full
    /// 2021/03/05
    case numeric
    /// 3年前
    case relative

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .full: return "完整日期"
        case .numeric: return "数字日期"
        case .relative: return "相对时间"
        }
    }
}

/// 所有使用者設定。解碼時缺少的欄位使用預設值，方便日後新增設定而不破壞舊資料。
public struct AppSettings: Codable, Equatable, Sendable {
    public static let groupSizeRange = 5...100
    public static let defaultGroupSize = 15

    public var groupSize: Int = AppSettings.defaultGroupSize {
        didSet { groupSize = AppSettings.clampGroupSize(groupSize) }
    }
    public var category: MediaCategory = .all

    // 手勢與回饋
    public var hapticsEnabled = true
    public var doubleTapToFavorite = true
    public var deleteAnimationEnabled = true

    // 顯示
    public var hdrEnabled = true
    public var hdrAutoOffInLowBrightness = true
    public var livePhotoAutoplay = true
    public var livePhotoMuted = true
    public var videoAutoplay = true
    public var videoMuted = false
    public var showDate = true
    public var dateStyle: DateDisplayStyle = .full

    // 同步與提醒
    public var iCloudSyncEnabled = false
    public var dailyReminderEnabled = false
    public var reminderHour = 21
    public var reminderMinute = 0

    /// 演示模式：用生成的示範卡片取代真實照片，方便錄屏、展示而不洩漏隱私。
    public var demoMode = false

    public init() {}

    public static func clampGroupSize(_ value: Int) -> Int {
        min(max(value, groupSizeRange.lowerBound), groupSizeRange.upperBound)
    }

    enum CodingKeys: String, CodingKey {
        case groupSize, category, hapticsEnabled, doubleTapToFavorite, deleteAnimationEnabled
        case hdrEnabled, hdrAutoOffInLowBrightness, livePhotoAutoplay, livePhotoMuted
        case videoAutoplay, videoMuted, showDate, dateStyle
        case iCloudSyncEnabled, dailyReminderEnabled, reminderHour, reminderMinute, demoMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        groupSize = AppSettings.clampGroupSize(try c.decodeIfPresent(Int.self, forKey: .groupSize) ?? d.groupSize)
        category = (try? c.decodeIfPresent(MediaCategory.self, forKey: .category)) ?? d.category
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? d.hapticsEnabled
        doubleTapToFavorite = try c.decodeIfPresent(Bool.self, forKey: .doubleTapToFavorite) ?? d.doubleTapToFavorite
        deleteAnimationEnabled = try c.decodeIfPresent(Bool.self, forKey: .deleteAnimationEnabled) ?? d.deleteAnimationEnabled
        hdrEnabled = try c.decodeIfPresent(Bool.self, forKey: .hdrEnabled) ?? d.hdrEnabled
        hdrAutoOffInLowBrightness = try c.decodeIfPresent(Bool.self, forKey: .hdrAutoOffInLowBrightness) ?? d.hdrAutoOffInLowBrightness
        livePhotoAutoplay = try c.decodeIfPresent(Bool.self, forKey: .livePhotoAutoplay) ?? d.livePhotoAutoplay
        livePhotoMuted = try c.decodeIfPresent(Bool.self, forKey: .livePhotoMuted) ?? d.livePhotoMuted
        videoAutoplay = try c.decodeIfPresent(Bool.self, forKey: .videoAutoplay) ?? d.videoAutoplay
        videoMuted = try c.decodeIfPresent(Bool.self, forKey: .videoMuted) ?? d.videoMuted
        showDate = try c.decodeIfPresent(Bool.self, forKey: .showDate) ?? d.showDate
        dateStyle = (try? c.decodeIfPresent(DateDisplayStyle.self, forKey: .dateStyle)) ?? d.dateStyle
        iCloudSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .iCloudSyncEnabled) ?? d.iCloudSyncEnabled
        dailyReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .dailyReminderEnabled) ?? d.dailyReminderEnabled
        reminderHour = min(max(try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? d.reminderHour, 0), 23)
        reminderMinute = min(max(try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? d.reminderMinute, 0), 59)
        demoMode = try c.decodeIfPresent(Bool.self, forKey: .demoMode) ?? d.demoMode
    }
}
