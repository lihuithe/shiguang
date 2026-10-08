import Observation
import ShiGuangCore
import SwiftUI

/// 首頁隨機瀏覽的狀態機：抽組 → 逐張滑動 → 結算刪除 → 下一組。
@MainActor
@Observable
final class BrowserViewModel {
    enum Phase: Equatable {
        case loading
        case empty
        case browsing
        case review
    }

    private(set) var phase: Phase = .loading
    private(set) var session = GroupSession(items: [])
    /// 這個類別都看過了，正在用最早看過的內容補齊
    private(set) var didRecycle = false
    private(set) var isDeleting = false
    var errorMessage: String?

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private var viewedInSession = Set<String>()

    init(model: AppModel) {
        self.model = model
    }

    var category: MediaCategory { model.settings.category }

    // MARK: - 抽組

    func startNewGroup() {
        phase = .loading
        let source = model.source(for: category)
        let result = GroupPicker.pick(
            from: source,
            history: model.history,
            size: model.settings.groupSize,
            excluding: Set(session.items.map(\.id))
        )
        // 排除上一組後若為空（例如整個類別只有一組），就不排除再抽一次
        let picked = result.items.isEmpty
            ? GroupPicker.pick(from: source, history: model.history, size: model.settings.groupSize)
            : result
        session = GroupSession(items: picked.items)
        didRecycle = picked.didRecycle
        viewedInSession.removeAll()
        phase = session.isEmpty ? .empty : .browsing
        currentDidChange()
    }

    /// 首頁選單切換分類；設定頁也能改，兩者都經由 `categoryDidChange` 重新抽組。
    func switchCategory(_ category: MediaCategory) {
        model.updateSettings { $0.category = category }
    }

    func categoryDidChange() {
        session = GroupSession(items: [])
        startNewGroup()
    }

    /// 相簿內容變化（例如在其他 App 刪了照片）時，移除已不存在的項目。
    func libraryDidChange() {
        guard !model.settings.demoMode, phase == .browsing || phase == .review else { return }
        let alive = session.items.filter { model.library.asset(withID: $0.id) != nil }
        if alive.count != session.items.count {
            session = GroupSession(items: alive)
            phase = alive.isEmpty ? .empty : .browsing
            currentDidChange()
        }
    }

    // MARK: - 手勢

    func perform(_ action: SwipeAction) {
        guard phase == .browsing, let item = session.current else { return }
        switch action {
        case .delete:
            Haptics.delete()
            session.markCurrentForDeletion()
        case .favorite:
            // 下滑：收藏並看下一張
            if !session.isFavorite(item.id) {
                toggleFavorite(item)
            } else {
                Haptics.favorite()
            }
            session.next()
        case .next:
            Haptics.tick()
            session.next()
        case .previous:
            guard session.canGoBack else { return }
            Haptics.tick()
            session.previous()
        case .none:
            return
        }
        currentDidChange()
    }

    func toggleFavorite(_ item: MediaItem) {
        let isFavorite = session.toggleFavorite(item.id)
        Haptics.favorite()
        model.setFavorite(isFavorite, item: item)
    }

    func toggleDeletion(_ item: MediaItem) {
        session.toggleDeletion(item.id)
        Haptics.tick()
    }

    func undo() {
        guard let event = session.undo() else { return }
        Haptics.tick()
        if case let .favoriteChanged(id, wasFavorite) = event,
           let item = session.items.first(where: { $0.id == id }) {
            model.setFavorite(wasFavorite, item: item)
        }
        if phase == .review, !session.isFinished {
            phase = .browsing
        }
        currentDidChange()
    }

    func jump(to item: MediaItem) {
        guard let index = session.items.firstIndex(of: item) else { return }
        session.jump(to: index)
        phase = .browsing
        currentDidChange()
    }

    func finishGroup() {
        session.finish()
        currentDidChange()
    }

    // MARK: - 結算

    /// 確認刪除本組標記的項目，成功後進入下一組。
    func confirmDeletionAndContinue() async {
        let pending = session.pendingDeletion
        if pending.isEmpty {
            completeGroup()
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let deleted = try await model.delete(pending)
            guard deleted else { return }
            Haptics.success()
            completeGroup()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    private func completeGroup() {
        model.recordGroupCompleted()
        startNewGroup()
    }

    func resetCategoryHistory() {
        model.resetHistory(for: category)
        session = GroupSession(items: [])
        startNewGroup()
    }

    // MARK: - 內部

    private func currentDidChange() {
        if let item = session.current, !viewedInSession.contains(item.id) {
            viewedInSession.insert(item.id)
            model.markViewed(item)
        }
        if session.isFinished, !session.isEmpty {
            if phase != .review { Haptics.success() }
            phase = .review
        } else if phase == .review {
            phase = .browsing
        }
        prefetchUpcoming()
    }

    private func prefetchUpcoming() {
        guard !model.settings.demoMode else { return }
        let start = session.currentIndex + 1
        guard start < session.items.count else { return }
        let ids = session.items[start..<min(start + 3, session.items.count)]
            .filter { $0.kind == .photo }
            .map(\.id)
        let scale = UIScreen.main.scale
        let size = UIScreen.main.bounds.size
        MediaLoader.shared.updatePrefetch(ids: Array(ids), targetSize: CGSize(width: size.width * scale, height: size.height * scale))
    }
}
