import Foundation

/// 一組照片（或影片）的瀏覽狀態。
///
/// 互動模型與原版一致：
/// - 左右（影片為上下）切換上一張 / 下一張；
/// - 上滑刪除後，該項目立即從序列中消失，下一張接上，可以撤銷；
/// - 滑過最後一張即「看完一組」，此時統一確認待刪除的項目。
public struct GroupSession: Equatable {
    public enum Event: Equatable {
        /// visibleIndex：刪除當下它在可見序列中的位置，撤銷時放回原位
        case deleted(id: String, visibleIndex: Int)
        case favoriteChanged(id: String, wasFavorite: Bool)
    }

    public private(set) var items: [MediaItem]
    public private(set) var markedForDeletion: Set<String> = []
    public private(set) var favorites: Set<String>
    /// 在 `visibleItems` 中的位置；等於 visibleItems.count 表示看完了
    public private(set) var currentIndex: Int = 0
    public private(set) var history: [Event] = []

    public init(items: [MediaItem]) {
        self.items = items
        self.favorites = Set(items.filter(\.isFavorite).map(\.id))
    }

    // MARK: - 查詢

    /// 尚未被標記刪除的項目，順序與原組一致
    public var visibleItems: [MediaItem] {
        items.filter { !markedForDeletion.contains($0.id) }
    }

    public var isEmpty: Bool { items.isEmpty }
    public var isFinished: Bool { currentIndex >= visibleItems.count }
    public var current: MediaItem? { item(atVisibleIndex: currentIndex) }
    public var previous: MediaItem? { item(atVisibleIndex: currentIndex - 1) }
    public var next: MediaItem? { item(atVisibleIndex: currentIndex + 1) }
    public var canGoBack: Bool { currentIndex > 0 && !visibleItems.isEmpty }
    public var canUndo: Bool { !history.isEmpty }

    public var pendingDeletion: [MediaItem] {
        items.filter { markedForDeletion.contains($0.id) }
    }

    /// 從目前位置開始的接下來幾項，首頁的扇形卡片用它預覽
    public func upcoming(_ count: Int) -> [MediaItem] {
        let visible = visibleItems
        guard currentIndex < visible.count, count > 0 else { return [] }
        return Array(visible[currentIndex..<min(currentIndex + count, visible.count)])
    }

    /// 還沒看到的數量（不含目前這張）
    public var remainingCount: Int {
        max(visibleItems.count - currentIndex - 1, 0)
    }

    /// 目前這張在整組中的進度，0...1，用於頂部進度條
    public var progress: Double {
        guard !items.isEmpty else { return 0 }
        guard let current, let position = items.firstIndex(of: current) else { return 1 }
        return Double(position + 1) / Double(items.count)
    }

    public func isMarkedForDeletion(_ id: String) -> Bool {
        markedForDeletion.contains(id)
    }

    public func isFavorite(_ id: String) -> Bool {
        favorites.contains(id)
    }

    private func item(atVisibleIndex index: Int) -> MediaItem? {
        let visible = visibleItems
        return visible.indices.contains(index) ? visible[index] : nil
    }

    // MARK: - 操作

    /// 上滑刪除：目前這張移出序列，下一張自動接上；若刪的是最後一張則看完一組。
    @discardableResult
    public mutating func deleteCurrent() -> MediaItem? {
        guard let item = current else { return nil }
        markedForDeletion.insert(item.id)
        history.append(.deleted(id: item.id, visibleIndex: currentIndex))
        return item
    }

    /// 下一張；在最後一張時呼叫即看完一組。翻頁不進撤銷記錄，撤銷只還原刪除與收藏。
    public mutating func goForward() {
        guard !isFinished else { return }
        currentIndex += 1
    }

    public mutating func goBack() {
        guard canGoBack else { return }
        currentIndex = min(currentIndex, visibleItems.count) - 1
    }

    /// 直接移到某個位置（原生分頁滾動停下時同步）；等於 visibleItems.count 表示滑到了組尾。
    public mutating func move(toVisibleIndex index: Int) {
        currentIndex = min(max(index, 0), visibleItems.count)
    }

    /// 收藏按鈕或雙擊：切換收藏。回傳切換後的狀態。
    @discardableResult
    public mutating func toggleFavorite(_ id: String) -> Bool {
        guard items.contains(where: { $0.id == id }) else { return false }
        let wasFavorite = favorites.contains(id)
        if wasFavorite { favorites.remove(id) } else { favorites.insert(id) }
        history.append(.favoriteChanged(id: id, wasFavorite: wasFavorite))
        return !wasFavorite
    }

    /// 撤銷上一步。回傳被撤銷的事件，App 層據此還原收藏等外部狀態。
    @discardableResult
    public mutating func undo() -> Event? {
        guard let last = history.popLast() else { return nil }
        switch last {
        case let .deleted(id, visibleIndex):
            markedForDeletion.remove(id)
            currentIndex = visibleIndex
        case let .favoriteChanged(id, wasFavorite):
            if wasFavorite { favorites.insert(id) } else { favorites.remove(id) }
        }
        return last
    }

    /// 在「有待刪除」清單中取消某一項的刪除（留下它）。
    public mutating func keep(_ id: String) {
        markedForDeletion.remove(id)
        currentIndex = min(currentIndex, visibleItems.count)
    }

    /// 項目已在外部被刪除（例如在「回到那天」或照片 App 裡刪的）：從組中移除，
    /// 保留目前位置、刪除標記與收藏。撤銷記錄因位置失效而清空。
    public mutating func removeExternally(_ ids: Set<String>) {
        let removed = ids.intersection(items.map(\.id))
        guard !removed.isEmpty else { return }
        let visibleBefore = visibleItems
        let currentID = current?.id
        items.removeAll { removed.contains($0.id) }
        markedForDeletion.subtract(removed)
        favorites.subtract(removed)
        history.removeAll()
        let visible = visibleItems
        if let currentID, let index = visible.firstIndex(where: { $0.id == currentID }) {
            currentIndex = index
        } else {
            // 目前這張被刪了：停在它原本位置上的下一張
            let survivorsBefore = visibleBefore.prefix(currentIndex).filter { !removed.contains($0.id) }.count
            currentIndex = min(survivorsBefore, visible.count)
        }
    }

    /// 看完後關掉待刪除清單：回到最後一張繼續看。
    public mutating func reopen() {
        guard isFinished else { return }
        currentIndex = max(visibleItems.count - 1, 0)
    }
}
