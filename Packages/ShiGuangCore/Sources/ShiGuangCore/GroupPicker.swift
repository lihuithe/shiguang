import Foundation

/// 可隨機存取的媒體來源。App 層以 PHFetchResult 包裝，避免一次把整個相簿轉成陣列。
public protocol MediaSource {
    var count: Int { get }
    func item(at index: Int) -> MediaItem
}

public struct ArrayMediaSource: MediaSource {
    public let items: [MediaItem]
    public init(_ items: [MediaItem]) { self.items = items }
    public var count: Int { items.count }
    public func item(at index: Int) -> MediaItem { items[index] }
}

public struct GroupPickResult: Equatable {
    public var items: [MediaItem]
    /// 未看過的內容不足一組，用最久以前看過的內容補齊。
    public var didRecycle: Bool

    public init(items: [MediaItem], didRecycle: Bool) {
        self.items = items
        self.didRecycle = didRecycle
    }
}

/// 隨機抽一組「盲盒」。
///
/// 1. 先隨機探測索引，挑出未看過的內容（大相簿裡通常很快就湊滿）；
/// 2. 探測不夠時，掃描剩餘全部索引；
/// 3. 整個類別都看過了，就用最久以前看過的內容補齊。
public enum GroupPicker {
    public static func pick<R: RandomNumberGenerator>(
        from source: MediaSource,
        history: ViewHistory,
        size: Int,
        now: Date,
        window: TimeInterval = ViewHistory.defaultRepeatWindow,
        excluding excluded: Set<String> = [],
        using rng: inout R
    ) -> GroupPickResult {
        let total = source.count
        let target = min(max(size, 1), total)
        guard target > 0 else { return GroupPickResult(items: [], didRecycle: false) }

        var chosen: [MediaItem] = []
        var tried = Set<Int>()
        var viewed: [(item: MediaItem, date: Date)] = []

        func consider(_ index: Int) {
            tried.insert(index)
            let item = source.item(at: index)
            if excluded.contains(item.id) { return }
            if history.hasViewed(item.id, now: now, window: window) {
                viewed.append((item, history.lastViewed(item.id) ?? .distantPast))
            } else {
                chosen.append(item)
            }
        }

        // 1. 隨機探測
        let maxAttempts = target * 30
        var attempts = 0
        while chosen.count < target, attempts < maxAttempts, tried.count < total {
            attempts += 1
            let index = Int.random(in: 0..<total, using: &rng)
            if tried.contains(index) { continue }
            consider(index)
        }

        // 2. 掃描剩餘索引
        if chosen.count < target, tried.count < total {
            var rest = (0..<total).filter { !tried.contains($0) }
            rest.shuffle(using: &rng)
            for index in rest where chosen.count < target {
                consider(index)
            }
        }

        // 3. 用最久以前看過的內容補齊
        var didRecycle = false
        if chosen.count < target, !viewed.isEmpty {
            didRecycle = true
            let needed = target - chosen.count
            let oldest = viewed.sorted { $0.date < $1.date }.prefix(needed).map(\.item)
            chosen.append(contentsOf: oldest)
        }

        chosen.shuffle(using: &rng)
        return GroupPickResult(items: chosen, didRecycle: didRecycle)
    }

    public static func pick(
        from source: MediaSource,
        history: ViewHistory,
        size: Int,
        now: Date = Date(),
        window: TimeInterval = ViewHistory.defaultRepeatWindow,
        excluding excluded: Set<String> = []
    ) -> GroupPickResult {
        var rng = SystemRandomNumberGenerator()
        return pick(from: source, history: history, size: size, now: now, window: window, excluding: excluded, using: &rng)
    }
}

/// 可重現的亂數產生器（SplitMix64），用於測試與演示模式。
public struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
