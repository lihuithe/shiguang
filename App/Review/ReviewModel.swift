import Observation
import ShiGuangCore
import SwiftUI

/// 照片分頁與視頻分頁共用的瀏覽狀態機：抽一組 → 翻看 / 刪除 → 看完確認刪除 → 下一組。
@MainActor
@Observable
final class ReviewModel {
    enum Kind {
        case photos
        case videos
    }

    let kind: Kind

    private(set) var session = GroupSession(items: [])
    private(set) var hasLoaded = false
    /// 這個分類都看過了，正在用最早看過的內容補齊
    private(set) var didRecycle = false
    /// 照片分頁：是否在全螢幕瀏覽中
    var isReviewing = false
    /// 看完一組（或中途返回）時，顯示「有待刪除的照片」
    var isPresentingPending = false
    private(set) var isDeleting = false
    /// 每次刪除遞增，畫面據此顯示「點擊撤銷」提示
    private(set) var deleteCount = 0
    /// 本次瀏覽看過的數量，用來決定何時顯示「回到那天」教學
    private(set) var viewedThisSession = 0
    var errorMessage: String?

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private var viewedIDs = Set<String>()

    init(kind: Kind, model: AppModel) {
        self.kind = kind
        self.model = model
    }

    var category: MediaCategory {
        kind == .videos ? .videos : model.settings.category
    }

    var noun: String {
        kind == .videos ? "视频" : "照片"
    }

    // MARK: - 抽組

    func loadIfNeeded() {
        guard !hasLoaded || session.isEmpty else { return }
        startNewGroup()
    }

    func startNewGroup() {
        let source = model.source(for: category)
        let previous = Set(session.items.map(\.id))
        var result = GroupPicker.pick(from: source, history: model.history, size: model.settings.groupSize, excluding: previous)
        // 排除上一組後為空（整個分類只有一組）就不排除
        if result.items.isEmpty {
            result = GroupPicker.pick(from: source, history: model.history, size: model.settings.groupSize)
        }
        session = GroupSession(items: result.items)
        didRecycle = result.didRecycle
        hasLoaded = true
        viewedIDs.removeAll()
        isPresentingPending = false
        prefetch()
    }

    /// 分類、演示模式切換，或重置瀏覽記錄後重新抽組
    func reload() {
        isReviewing = false
        session = GroupSession(items: [])
        startNewGroup()
    }

    /// 相簿內容變化（例如在其他 App 刪了照片）時，移除已不存在的項目。
    func libraryDidChange() {
        guard !model.settings.demoMode, hasLoaded, !isDeleting else { return }
        let removed = Set(session.items.filter { model.library.asset(withID: $0.id) == nil }.map(\.id))
        guard !removed.isEmpty else { return }
        session.removeExternally(removed)
        if session.isEmpty {
            isReviewing = false
            startNewGroup()
        } else if session.isFinished, isReviewing || kind == .videos {
            finishGroup()
        }
    }

    // MARK: - 瀏覽

    /// 照片首頁輕觸卡片：進入全螢幕瀏覽
    func beginReview() {
        if session.isEmpty || session.isFinished { startNewGroup() }
        guard !session.isEmpty else { return }
        isReviewing = true
        markCurrentViewed()
    }

    /// 視頻分頁出現時記錄目前這支
    func markCurrentViewed() {
        guard let item = session.current, !viewedIDs.contains(item.id) else { return }
        viewedIDs.insert(item.id)
        viewedThisSession += 1
        model.markViewed(item)
        model.locations.resolve(item)
        if let next = session.next { model.locations.resolve(next) }
    }

    /// 原生分頁滾動停在某一項上時同步位置
    func move(to id: String) {
        guard let index = session.visibleItems.firstIndex(where: { $0.id == id }),
              index != session.currentIndex else { return }
        session.move(toVisibleIndex: index)
        afterMove()
    }

    /// 滑到組尾的結束頁：看完一組
    func reachEnd() {
        guard !session.isFinished else { return }
        session.move(toVisibleIndex: session.visibleItems.count)
        afterMove()
    }

    func deleteCurrent() {
        guard session.deleteCurrent() != nil else { return }
        Haptics.delete()
        deleteCount += 1
        afterMove()
    }

    func toggleFavorite(_ item: MediaItem) {
        let isFavorite = session.toggleFavorite(item.id)
        Haptics.favorite()
        model.setFavorite(isFavorite, item: item)
    }

    func undo() {
        guard let event = session.undo() else { return }
        Haptics.tick()
        if case let .favoriteChanged(id, wasFavorite) = event,
           let item = session.items.first(where: { $0.id == id }) {
            model.setFavorite(wasFavorite, item: item)
        }
        isPresentingPending = false
        afterMove()
    }

    private func afterMove() {
        markCurrentViewed()
        if session.isFinished {
            finishGroup()
        }
        prefetch()
    }

    private func finishGroup() {
        if session.pendingDeletion.isEmpty {
            Haptics.success()
            completeGroup()
        } else {
            isPresentingPending = true
        }
    }

    // MARK: - 結束一組

    /// 返回鍵：有待刪除的項目就先確認，否則直接回首頁（下次輕觸接著看）。
    func requestExit() {
        if session.pendingDeletion.isEmpty {
            isReviewing = false
        } else {
            isPresentingPending = true
        }
    }

    /// 關閉待刪除清單（右上角 ×）：回到瀏覽
    func closePending() {
        isPresentingPending = false
        session.reopen()
        markCurrentViewed()
    }

    /// 「放棄，回到首頁」：不刪除，結束這一組
    func discardPending() {
        completeGroup()
    }

    /// 「確認刪除」：刪除勾選的項目（系統會再確認一次），成功後結束這一組
    func confirmDeletion(of items: [MediaItem]) async {
        guard !items.isEmpty else {
            completeGroup()
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        do {
            guard try await model.delete(items) else { return }
            Haptics.success()
            completeGroup()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    private func completeGroup() {
        model.recordGroupCompleted()
        isPresentingPending = false
        if kind == .photos {
            isReviewing = false
        }
        startNewGroup()
        if kind == .videos {
            markCurrentViewed()
        }
    }

    func resetHistoryAndReload() {
        model.resetHistory(for: category)
        reload()
    }

    // MARK: - 預載

    private func prefetch() {
        guard !model.settings.demoMode else { return }
        let ids = session.upcoming(4).dropFirst().filter { $0.kind == .photo }.map(\.id)
        guard !ids.isEmpty else { return }
        let scale = UIScreen.main.scale
        let size = UIScreen.main.bounds.size
        MediaLoader.shared.updatePrefetch(ids: Array(ids), targetSize: CGSize(width: size.width * scale, height: size.height * scale))
    }
}
