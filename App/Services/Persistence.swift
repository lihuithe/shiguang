import Foundation
import ShiGuangCore

/// 把 Codable 值存成 Application Support 下的 JSON 檔。
struct JSONFileStore<Value: Codable> {
    let url: URL

    init(filename: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShiGuang", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent(filename)
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// 透過 iCloud 鍵值儲存同步瀏覽記錄，讓多台裝置共享「看過哪些」。
///
/// NSUbiquitousKeyValueStore 單一值上限 1 MB，超過時只保留最近的記錄。
final class HistorySyncService {
    private let store = NSUbiquitousKeyValueStore.default
    private let key = "viewHistory.v1"
    private let maxBytes = 900_000
    private var observer: NSObjectProtocol?

    /// 收到其他裝置的變更時在主執行緒回呼
    var onRemoteChange: ((ViewHistory) -> Void)?

    var isRunning: Bool { observer != nil }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            guard let self, let remote = self.pull() else { return }
            self.onRemoteChange?(remote)
        }
        store.synchronize()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func pull() -> ViewHistory? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ViewHistory.self, from: data)
    }

    func push(_ history: ViewHistory) {
        guard isRunning else { return }
        let encoder = JSONEncoder()
        guard var data = try? encoder.encode(history) else { return }
        if data.count > maxBytes {
            // 只保留最近看過的一部分
            let ratio = Double(maxBytes) / Double(data.count) * 0.9
            let keep = Int(Double(history.records.count) * ratio)
            let recent = history.records.sorted { $0.value > $1.value }.prefix(keep)
            let trimmed = ViewHistory(
                records: Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) }),
                tombstones: history.tombstones,
                resetAllAt: history.resetAllAt
            )
            guard let smaller = try? encoder.encode(trimmed), smaller.count <= maxBytes else { return }
            data = smaller
        }
        store.set(data, forKey: key)
        store.synchronize()
    }
}
