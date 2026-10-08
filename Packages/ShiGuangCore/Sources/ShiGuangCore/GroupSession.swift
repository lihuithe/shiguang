import Foundation

/// 一組照片的瀏覽狀態：目前位置、標記刪除、收藏，以及撤銷。
///
/// 刪除不會立即執行，而是在一組看完後統一確認，與原版「看完一組再批量刪除」一致。
public struct GroupSession: Equatable {
    public enum Event: Equatable {
        case markedForDeletion(id: String, fromIndex: Int)
        case unmarkedForDeletion(id: String, fromIndex: Int)
        case moved(fromIndex: Int)
        case favoriteChanged(id: String, wasFavorite: Bool)
    }

    public let items: [MediaItem]
    public private(set) var currentIndex: Int = 0
    public private(set) var markedForDeletion: Set<String> = []
    public private(set) var favorites: Set<String>
    public private(set) var history: [Event] = []

    public init(items: [MediaItem]) {
        self.items = items
        self.favorites = Set(items.filter(\.isFavorite).map(\.id))
    }

    public var isEmpty: Bool { items.isEmpty }
    public var isFinished: Bool { currentIndex >= items.count }
    public var current: MediaItem? { isFinished ? nil : items[currentIndex] }
    public var canGoBack: Bool { currentIndex > 0 }
    public var canUndo: Bool { !history.isEmpty }

    /// 進度，例如 3/15。
    public var progressText: String {
        "\(min(currentIndex + 1, items.count))/\(items.count)"
    }

    public var pendingDeletion: [MediaItem] {
        items.filter { markedForDeletion.contains($0.id) }
    }

    public func isMarkedForDeletion(_ id: String) -> Bool {
        markedForDeletion.contains(id)
    }

    public func isFavorite(_ id: String) -> Bool {
        favorites.contains(id)
    }

    /// 上滑：標記目前這張為待刪除，並前進到下一張。
    public mutating func markCurrentForDeletion() {
        guard let item = current else { return }
        markedForDeletion.insert(item.id)
        history.append(.markedForDeletion(id: item.id, fromIndex: currentIndex))
        currentIndex += 1
    }

    /// 左滑：保留並看下一張。
    public mutating func next() {
        guard !isFinished else { return }
        history.append(.moved(fromIndex: currentIndex))
        currentIndex += 1
    }

    /// 右滑：回到上一張。
    public mutating func previous() {
        guard canGoBack else { return }
        history.append(.moved(fromIndex: currentIndex))
        currentIndex -= 1
    }

    /// 跳到組內任意位置（例如結算頁點擊縮圖回看）。
    public mutating func jump(to index: Int) {
        guard items.indices.contains(index), index != currentIndex else { return }
        history.append(.moved(fromIndex: currentIndex))
        currentIndex = index
    }

    /// 在結算頁切換某一項的刪除標記。
    public mutating func toggleDeletion(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        if markedForDeletion.contains(id) {
            markedForDeletion.remove(id)
            history.append(.unmarkedForDeletion(id: id, fromIndex: currentIndex))
        } else {
            markedForDeletion.insert(id)
            history.append(.markedForDeletion(id: id, fromIndex: currentIndex))
        }
    }

    /// 下滑或雙擊：切換收藏。回傳切換後的狀態。
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
        case let .markedForDeletion(id, fromIndex):
            markedForDeletion.remove(id)
            currentIndex = fromIndex
        case let .unmarkedForDeletion(id, fromIndex):
            markedForDeletion.insert(id)
            currentIndex = fromIndex
        case let .moved(fromIndex):
            currentIndex = fromIndex
        case let .favoriteChanged(id, wasFavorite):
            if wasFavorite { favorites.insert(id) } else { favorites.remove(id) }
        }
        return last
    }

    /// 把位置移到結尾，進入結算。
    public mutating func finish() {
        guard !isFinished else { return }
        history.append(.moved(fromIndex: currentIndex))
        currentIndex = items.count
    }
}
