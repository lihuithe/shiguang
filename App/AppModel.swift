import Observation
import Photos
import ShiGuangCore
import SwiftUI

/// 全域狀態：設定、瀏覽記錄、統計，以及 PhotoKit 與 iCloud 同步服務。
@MainActor
@Observable
final class AppModel {
    /// 透過 `updateSettings` 或 `binding(_:)` 修改，以便儲存並處理副作用。
    private(set) var settings: AppSettings
    private(set) var history: ViewHistory
    private(set) var stats: UsageStats
    private(set) var authorization: PHAuthorizationStatus
    /// 相簿內容變化時遞增，畫面據此刷新
    private(set) var libraryVersion = 0
    private(set) var screenBrightness: CGFloat = UIScreen.main.brightness
    var reminderError: String?

    let library = PhotoLibraryService()
    let locations = LocationNamer()
    let calendar = Calendar.current

    @ObservationIgnored private let sync = HistorySyncService()
    @ObservationIgnored private let historyStore: JSONFileStore<ViewHistory>
    @ObservationIgnored private let statsStore: JSONFileStore<UsageStats>
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var brightnessObserver: NSObjectProtocol?
    @ObservationIgnored private var demoItems: [MediaItem] = []

    private static let settingsKey = "settings.v1"

    init() {
        let historyStore = JSONFileStore<ViewHistory>(filename: "history.json")
        let statsStore = JSONFileStore<UsageStats>(filename: "stats.json")
        var loadedSettings = AppSettings()
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            loadedSettings = saved
        }
        self.historyStore = historyStore
        self.statsStore = statsStore
        settings = loadedSettings
        history = historyStore.load() ?? ViewHistory()
        stats = statsStore.load() ?? UsageStats()
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        demoItems = DemoLibrary.items()
        Haptics.isEnabled = settings.hapticsEnabled

        library.onChange = { [weak self] in
            self?.libraryVersion += 1
        }
        library.registerIfNeeded()

        sync.onRemoteChange = { [weak self] remote in
            self?.mergeRemoteHistory(remote)
        }
        if settings.iCloudSyncEnabled {
            startSync()
        }

        brightnessObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.brightnessDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screenBrightness = UIScreen.main.brightness
            }
        }
    }

    // MARK: - 權限

    var hasLibraryAccess: Bool {
        authorization == .authorized || authorization == .limited
    }

    /// 演示模式不需要相簿權限
    var canBrowse: Bool {
        settings.demoMode || hasLibraryAccess
    }

    func requestLibraryAccess() async {
        authorization = await library.requestAccess()
        libraryVersion += 1
    }

    func refreshAuthorization() {
        authorization = library.status
        library.registerIfNeeded()
    }

    // MARK: - 媒體來源

    func source(for category: MediaCategory) -> MediaSource {
        if settings.demoMode {
            return ArrayMediaSource(demoItems.filter(category.contains))
        }
        return library.source(for: category)
    }

    func dayItems(for date: Date) -> [MediaItem] {
        if settings.demoMode {
            let range = DayBucket.range(containing: date, calendar: calendar)
            return DayBucket.sortedChronologically(demoItems.filter { item in
                guard let d = item.creationDate else { return false }
                return range.contains(d) && d < range.end
            })
        }
        return library.assets(onDayOf: date, calendar: calendar).map { MediaItem(asset: $0) }
    }

    func removeDemoItems(ids: Set<String>) {
        demoItems.removeAll { ids.contains($0.id) }
    }

    /// 低亮度時自動關閉 HDR，避免刺眼。
    var effectiveHDR: Bool {
        settings.hdrEnabled && !(settings.hdrAutoOffInLowBrightness && screenBrightness < 0.3)
    }

    // MARK: - 記錄

    func markViewed(_ item: MediaItem) {
        let now = Date()
        history.markViewed(item.id, at: now)
        stats.recordViewed(StatsBucket(item: item), at: now, calendar: calendar)
        scheduleSave()
    }

    /// 按「照片 / 截屏 / 視頻」分類記錄刪除數量與騰出的空間
    private func recordDeleted(_ items: [MediaItem], sizes: [String: Int64]) {
        let now = Date()
        for bucket in StatsBucket.allCases {
            let matched = items.filter { StatsBucket(item: $0) == bucket }
            guard !matched.isEmpty else { continue }
            let bytes = matched.reduce(Int64(0)) { $0 + (sizes[$1.id] ?? 0) }
            stats.recordDeleted(bucket, count: matched.count, bytes: bytes, at: now, calendar: calendar)
        }
        scheduleSave()
    }

    func recordFavoriteChange(isFavorite: Bool) {
        stats.recordFavorited(count: isFavorite ? 1 : -1, at: Date(), calendar: calendar)
        scheduleSave()
    }

    func recordGroupCompleted() {
        stats.recordGroupCompleted()
        scheduleSave()
    }

    /// 刪除媒體（演示模式下只是從假相簿移除）。成功時回傳 true；使用者在系統確認框取消時回傳 false。
    func delete(_ items: [MediaItem]) async throws -> Bool {
        let ids = items.map(\.id)
        guard !ids.isEmpty else { return true }
        if settings.demoMode {
            removeDemoItems(ids: Set(ids))
            let sizes = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.kind == .video ? Int64(24_000_000) : Int64(3_200_000)) })
            recordDeleted(items, sizes: sizes)
            return true
        }
        let sizes = library.estimatedFileSizes(ids: ids)
        do {
            try await library.delete(ids: ids)
        } catch PhotoLibraryError.userCancelled {
            return false
        }
        recordDeleted(items, sizes: sizes)
        return true
    }

    func setFavorite(_ favorite: Bool, item: MediaItem) {
        recordFavoriteChange(isFavorite: favorite)
        guard !settings.demoMode else { return }
        Task {
            try? await library.setFavorite(favorite, id: item.id)
        }
    }

    // MARK: - 重置

    func resetHistory(for category: MediaCategory) {
        let now = Date()
        if category == .all {
            history.resetAll(at: now)
        } else if settings.demoMode {
            history.reset(ids: demoItems.filter(category.contains).map(\.id), at: now)
        } else {
            history.reset(ids: library.allAssetIDs(in: category), at: now)
        }
        saveNow()
    }

    /// 清掉已不存在的媒體記錄，避免檔案越來越大。
    func pruneHistory() {
        guard !settings.demoMode, hasLibraryAccess else { return }
        let ids = Set(library.allAssetIDs(in: .all))
        guard !ids.isEmpty else { return }
        history.prune(keeping: ids)
        scheduleSave()
    }

    // MARK: - 儲存與同步

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        historyStore.save(history)
        statsStore.save(stats)
        sync.push(history)
    }

    private func startSync() {
        sync.start()
        if let remote = sync.pull() {
            mergeRemoteHistory(remote)
        } else {
            sync.push(history)
        }
    }

    private func mergeRemoteHistory(_ remote: ViewHistory) {
        let merged = history.merged(with: remote)
        guard merged != history else { return }
        history = merged
        historyStore.save(history)
    }

    // MARK: - 設定

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        let old = settings
        settings = copy
        settingsDidChange(from: old)
    }

    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func settingsDidChange(from old: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        Haptics.isEnabled = settings.hapticsEnabled

        if settings.iCloudSyncEnabled != old.iCloudSyncEnabled {
            if settings.iCloudSyncEnabled { startSync() } else { sync.stop() }
        }

        let reminderChanged = settings.dailyReminderEnabled != old.dailyReminderEnabled
            || settings.reminderHour != old.reminderHour
            || settings.reminderMinute != old.reminderMinute
        if reminderChanged {
            updateReminder()
        }
    }

    private func updateReminder() {
        guard settings.dailyReminderEnabled else {
            ReminderService.cancel()
            return
        }
        let hour = settings.reminderHour, minute = settings.reminderMinute
        Task {
            let ok = await ReminderService.schedule(hour: hour, minute: minute)
            if !ok {
                reminderError = "没有通知权限，请在系统设置中允许拾光发送通知。"
                updateSettings { $0.dailyReminderEnabled = false }
            }
        }
    }
}
