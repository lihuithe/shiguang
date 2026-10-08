import ShiGuangCore
import SwiftUI

/// 「回到那天」的篩選
enum TimelineFilter: String, CaseIterable, Identifiable {
    case all, photos, videos, screenshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .photos: return "照片"
        case .videos: return "视频"
        case .screenshots: return "截图"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .photos: return "photo"
        case .videos: return "video"
        case .screenshots: return "camera.viewfinder"
        }
    }

    func contains(_ item: MediaItem) -> Bool {
        switch self {
        case .all: return true
        case .photos: return MediaCategory.photos.contains(item)
        case .videos: return item.kind == .video
        case .screenshots: return item.isScreenshot
        }
    }
}

/// 「回到那天」（對照原版）：
/// - 雙指捏合後，照片縮進一條左右滑動的多排時間軸，前後的日子都能一路滑過去，頂部日期跟著變；
/// - 頂部：返回、篩選、日期、完成；底部：回到起點、時間刻度尺、撤銷；
/// - 格子上滑刪除，雙指縮放調整格子大小（放大到底就回到照片），輕點放大查看。
struct DayTimelineView: View {
    let anchor: MediaItem
    /// 打開時照片卡片在螢幕上的位置，用於縮放過場；nil 表示直接淡入
    let sourceFrame: CGRect?
    let onClose: () -> Void

    struct PreviewTarget: Identifiable {
        let id: String
        let items: [MediaItem]
    }

    @Environment(AppModel.self) private var model
    @AppStorage("hint.timeline") private var hasSeenTimelineHint = false
    @Namespace private var zoomNamespace

    @State private var allItems: [MediaItem] = []
    /// 已上滑刪除、等待確認的項目（依刪除順序，供撤銷）
    @State private var pending: [String] = []
    @State private var filter: TimelineFilter = .all
    @State private var rows = 2
    @State private var scroll = ScrollPosition(idType: String.self)
    @State private var offsetX: CGFloat = 0
    @State private var areaFrame: CGRect = .zero
    @State private var contentOpacity: Double = 0
    @State private var heroFrame: CGRect?
    @State private var isClosing = false
    @State private var isDeleting = false
    @State private var confirmLeave = false
    @State private var preview: PreviewTarget?
    @State private var glow = false
    @State private var titleKey = ""

    private var visible: [MediaItem] {
        let removed = Set(pending)
        return allItems.filter { !removed.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Color(white: 0.08)
                .ignoresSafeArea()
                .opacity(contentOpacity)

            VStack(spacing: 0) {
                topBar
                gridArea
                if !hasSeenTimelineHint, contentOpacity > 0 {
                    hintBanner
                }
                bottomBar
            }
            .opacity(contentOpacity)

            IslandGlow(isOn: glow)
        }
        .overlay { heroLayer }
        .preferredColorScheme(.dark)
        .task { await open() }
        .fullScreenCover(item: $preview) { target in
            TimelinePreview(items: target.items, startID: target.id) { item in
                markDeleted(item)
            }
            .environment(model)
            .navigationTransition(.zoom(sourceID: target.id, in: zoomNamespace))
        }
        .onChange(of: titleKey) { old, _ in
            if !old.isEmpty { Haptics.tick() }
        }
    }

    // MARK: - 排版

    private struct Metrics {
        var rowHeight: CGFloat
        var spacing: CGFloat
        var contentHeight: CGFloat
    }

    private func metrics(for size: CGSize) -> Metrics {
        let spacing: CGFloat = 4
        let preferred: CGFloat = rows <= 2 ? min(size.width * 0.6, 230) : min(size.width * 0.4, 150)
        let fit = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(max(rows, 1))
        let rowHeight = max(min(preferred, fit), 60)
        return Metrics(rowHeight: rowHeight, spacing: spacing, contentHeight: CGFloat(rows) * rowHeight + CGFloat(rows - 1) * spacing)
    }

    private var currentMetrics: Metrics { metrics(for: areaFrame.size) }

    private var currentLayout: TimelineLayout {
        let m = currentMetrics
        return TimelineLayout(items: visible, rows: rows, rowHeight: Double(m.rowHeight), spacing: Double(m.spacing))
    }

    private var gridArea: some View {
        let items = visible
        let m = currentMetrics
        let layout = TimelineLayout(items: items, rows: rows, rowHeight: Double(m.rowHeight), spacing: Double(m.spacing))
        let rowIndices: [[Int]] = (0..<rows).map { row in
            layout.frames.indices.filter { layout.frames[$0].row == row }
        }
        return ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: m.spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    LazyHStack(spacing: m.spacing) {
                        ForEach(rowIndices[row], id: \.self) { index in
                            let item = items[index]
                            TimelineTile(
                                item: item,
                                width: CGFloat(layout.frames[index].width),
                                height: m.rowHeight,
                                isAnchor: item.id == anchor.id,
                                isHidden: heroFrame != nil && item.id == anchor.id,
                                onTap: { openPreview(item) },
                                onDelete: { markDeleted(item) }
                            )
                            .matchedTransitionSource(id: item.id, in: zoomNamespace)
                        }
                    }
                    .frame(height: m.rowHeight)
                }
            }
            .animation(.spring(duration: 0.35), value: items.map(\.id))
        }
        .scrollPosition($scroll)
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.x
        } action: { _, x in
            offsetX = x
            updateTitle()
        }
        .frame(height: m.contentHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            areaFrame = frame
        }
        .simultaneousGesture(
            MagnifyGesture().onEnded { value in
                handlePinch(value.magnification)
            }
        )
        .onChange(of: rows) { _, _ in
            // 換排數後保持原本位於中央的內容
            if let id = centerItem?.id { center(on: id, animated: false) }
        }
    }

    private var centerItem: MediaItem? {
        let items = visible
        guard let index = currentLayout.index(nearestX: Double(offsetX + areaFrame.width / 2)),
              items.indices.contains(index) else { return items.first }
        return items[index]
    }

    private func updateTitle() {
        guard let date = centerItem?.creationDate else { return }
        let c = model.calendar.dateComponents([.year, .month, .day], from: date)
        titleKey = "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 某一項在螢幕上的位置（以排版計算，不依賴量測）
    private func globalFrame(of id: String) -> CGRect? {
        let items = visible
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let m = currentMetrics
        let frame = currentLayout.frames[index]
        let gridMinY = areaFrame.midY - m.contentHeight / 2
        return CGRect(
            x: areaFrame.minX + CGFloat(frame.x) - offsetX,
            y: gridMinY + CGFloat(frame.row) * (m.rowHeight + m.spacing),
            width: CGFloat(frame.width),
            height: m.rowHeight
        )
    }

    private func center(on id: String, animated: Bool) {
        guard let index = visible.firstIndex(where: { $0.id == id }), areaFrame.width > 0 else { return }
        let target = CGFloat(currentLayout.offset(centering: index, viewportWidth: Double(areaFrame.width)))
        if animated {
            withAnimation(.spring(duration: 0.45)) { scroll.scrollTo(x: target) }
        } else {
            scroll.scrollTo(x: target)
        }
        offsetX = target
        updateTitle()
    }

    // MARK: - 打開與關閉（縮放過場）

    private func open() async {
        load(centerOn: anchor)
        // 等第一次排版拿到區域大小後再定位
        for _ in 0..<10 where areaFrame.width == 0 {
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        center(on: anchor.id, animated: false)

        guard let sourceFrame, let target = globalFrame(of: anchor.id) else {
            withAnimation(.easeOut(duration: 0.25)) { contentOpacity = 1 }
            return
        }
        heroFrame = sourceFrame
        try? await Task.sleep(nanoseconds: 16_000_000)
        withAnimation(.spring(duration: 0.45, bounce: 0.12)) {
            heroFrame = target
            contentOpacity = 1
        } completion: {
            heroFrame = nil
        }
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        if let sourceFrame, !pending.contains(anchor.id),
           let tile = globalFrame(of: anchor.id), tile.intersects(areaFrame) {
            heroFrame = tile
            withAnimation(.spring(duration: 0.4, bounce: 0.08)) {
                heroFrame = sourceFrame
                contentOpacity = 0
            } completion: {
                onClose()
            }
        } else {
            withAnimation(.easeOut(duration: 0.22)) {
                contentOpacity = 0
            } completion: {
                onClose()
            }
        }
    }

    @ViewBuilder
    private var heroLayer: some View {
        GeometryReader { proxy in
            if let heroFrame {
                let origin = proxy.frame(in: .global).origin
                AssetFillImage(item: anchor, side: 600)
                    .frame(width: heroFrame.width, height: heroFrame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .position(x: heroFrame.midX - origin.x, y: heroFrame.midY - origin.y)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - 資料

    private func load(centerOn item: MediaItem) {
        allItems = model.timeline(around: item, filter: filter).items
    }

    private func changeFilter(_ newFilter: TimelineFilter) {
        guard newFilter != filter else { return }
        let reference = centerItem ?? anchor
        filter = newFilter
        load(centerOn: reference)
        let target = visible.contains(where: { $0.id == reference.id }) ? reference.id : centerItem?.id
        Task {
            try? await Task.sleep(nanoseconds: 16_000_000)
            if let target { center(on: target, animated: false) }
        }
    }

    private func markDeleted(_ item: MediaItem) {
        guard !pending.contains(item.id) else { return }
        withAnimation(.spring(duration: 0.35)) {
            pending.append(item.id)
        }
        hasSeenTimelineHint = true
        Haptics.delete()
        glow = true
        Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            glow = false
        }
    }

    private func undo() {
        guard !pending.isEmpty else { return }
        withAnimation(.spring(duration: 0.35)) {
            _ = pending.removeLast()
        }
        Haptics.tick()
    }

    private func openPreview(_ item: MediaItem) {
        Haptics.tick()
        preview = PreviewTarget(id: item.id, items: visible)
    }

    private func handlePinch(_ magnification: CGFloat) {
        if magnification < 0.85, rows < 3 {
            withAnimation(.spring(duration: 0.4)) { rows += 1 }
            Haptics.tick()
        } else if magnification > 1.2 {
            if rows > 2 {
                withAnimation(.spring(duration: 0.4)) { rows -= 1 }
                Haptics.tick()
            } else {
                // 放大到底：回到照片
                requestLeave()
            }
        }
    }

    /// 返回：有待刪除的項目就先問一下
    private func requestLeave() {
        if pending.isEmpty {
            close()
        } else {
            confirmLeave = true
        }
    }

    /// ✓：確認刪除（系統會再問一次）並回到照片
    private func finish() {
        guard !pending.isEmpty else {
            close()
            return
        }
        let ids = Set(pending)
        let targets = allItems.filter { ids.contains($0.id) }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            guard (try? await model.delete(targets)) == true else { return }
            Haptics.success()
            allItems.removeAll { ids.contains($0.id) }
            pending.removeAll()
            close()
        }
    }

    // MARK: - 頂部與底部

    private var topBar: some View {
        ZStack {
            HStack(spacing: 10) {
                CircleIconButton(systemName: "chevron.left", size: 42) {
                    requestLeave()
                }
                .confirmationDialog(
                    "还有 \(pending.count) 张待删除",
                    isPresented: $confirmLeave,
                    titleVisibility: .visible
                ) {
                    Button("删除并返回", role: .destructive) { finish() }
                    Button("不删除，直接返回") {
                        pending.removeAll()
                        close()
                    }
                    Button("继续整理", role: .cancel) {}
                }

                Menu {
                    Picker("筛选", selection: Binding(get: { filter }, set: { changeFilter($0) })) {
                        ForEach(TimelineFilter.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .glassBackground(Circle())
                }

                Spacer()

                Button {
                    finish()
                } label: {
                    Group {
                        if isDeleting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(pending.isEmpty ? .white : .red)
                        }
                    }
                    .frame(width: 42, height: 42)
                    .glassBackground(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
            }

            VStack(spacing: 1) {
                Text("回到那天")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Text(titleKey.isEmpty ? " " : titleKey)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: titleKey)
            }
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var hintBanner: some View {
        HStack(spacing: 14) {
            Label("上滑删除", systemImage: "arrow.up")
            Label("双指缩放调整大小", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassBackground(Capsule(), interactive: false)
        .padding(.bottom, 10)
        .transition(.opacity)
    }

    private var bottomBar: some View {
        let layout = currentLayout
        let maxOffset = max(CGFloat(layout.contentWidth) - areaFrame.width, 1)
        return HStack(spacing: 14) {
            CircleIconButton(systemName: "arrow.counterclockwise", size: 46) {
                Haptics.tick()
                center(on: anchor.id, animated: true)
            }
            .disabled(pending.contains(anchor.id))

            TimelineRuler(fraction: Double(min(max(offsetX / maxOffset, 0), 1))) { fraction in
                let target = CGFloat(fraction) * maxOffset
                scroll.scrollTo(x: target)
                offsetX = target
                updateTitle()
            }
            .frame(height: 46)

            CircleIconButton(systemName: "arrow.uturn.backward", size: 46) {
                undo()
            }
            .disabled(pending.isEmpty)
            .opacity(pending.isEmpty ? 0.35 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - 格子

/// 時間軸上的一格：輕點放大查看，上滑刪除。
private struct TimelineTile: View {
    let item: MediaItem
    let width: CGFloat
    let height: CGFloat
    let isAnchor: Bool
    let isHidden: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var dragY: CGFloat = 0
    @State private var isVertical: Bool?
    @State private var flying = false

    var body: some View {
        AssetFillImage(item: item, side: max(width, height))
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                if item.kind == .video {
                    tag("视频", systemImage: "video.fill")
                } else if item.isLivePhoto {
                    tag("实况", systemImage: "livephoto")
                }
            }
            .overlay {
                if isAnchor {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(flying ? 0.3 : 1 - min(max(-dragY / 500, 0), 0.25))
            .offset(y: dragY)
            .opacity(isHidden || flying ? 0 : 1)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard !flying else { return }
                        if isVertical == nil {
                            let dx = value.translation.width, dy = value.translation.height
                            isVertical = dy < 0 && abs(dy) > abs(dx) * 1.2
                        }
                        guard isVertical == true else { return }
                        let dy = value.translation.height
                        dragY = dy < 0 ? dy : dy * 0.15
                    }
                    .onEnded { value in
                        let wasVertical = isVertical == true
                        isVertical = nil
                        guard wasVertical else { return }
                        if value.translation.height < -70 || value.predictedEndTranslation.height < -220 {
                            withAnimation(.easeIn(duration: 0.25)) {
                                dragY = -700
                                flying = true
                            } completion: {
                                onDelete()
                            }
                        } else {
                            withAnimation(.spring(duration: 0.3, bounce: 0.3)) { dragY = 0 }
                        }
                    }
            )
    }

    private func tag(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(6)
    }
}

/// 底部時間刻度尺：拖動快速穿越時間，亮線標示目前位置。
private struct TimelineRuler: View {
    let fraction: Double
    let onScrub: (Double) -> Void

    private let tickCount = 36

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 16
            let width = max(proxy.size.width - inset * 2, 1)
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<tickCount, id: \.self) { index in
                        Capsule()
                            .fill(.white.opacity(index % 6 == 0 ? 0.55 : 0.3))
                            .frame(width: 1.5, height: index % 6 == 0 ? 18 : 12)
                            .frame(maxWidth: .infinity)
                    }
                }
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: 24)
                    .offset(x: CGFloat(fraction) * width - 1.5)
            }
            .padding(.horizontal, inset)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onScrub(min(max(Double((value.location.x - inset) / width), 0), 1))
                    }
            )
        }
        .glassBackground(Capsule())
    }
}

// MARK: - 放大查看

/// 在時間軸上輕點某一格後放大查看：左右翻看、上滑刪除（加入時間軸的待刪除）。
private struct TimelinePreview: View {
    let startID: String
    let onDelete: (MediaItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var items: [MediaItem]
    @State private var position: String?
    @State private var favorites: Set<String>
    @State private var glow = false

    init(items: [MediaItem], startID: String, onDelete: @escaping (MediaItem) -> Void) {
        self.startID = startID
        self.onDelete = onDelete
        _items = State(initialValue: items)
        _position = State(initialValue: startID)
        _favorites = State(initialValue: Set(items.filter(\.isFavorite).map(\.id)))
    }

    private var current: MediaItem? {
        items.first { $0.id == position }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    CircleIconButton(systemName: "chevron.down", size: 40) { dismiss() }
                    Spacer()
                    if let date = current?.creationDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    if let current {
                        let isFavorite = favorites.contains(current.id)
                        CircleIconButton(systemName: isFavorite ? "heart.fill" : "heart", size: 40, tint: isFavorite ? .pink : .white) {
                            toggleFavorite(current)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                SwipePager(
                    items: items,
                    position: $position,
                    showsEndPage: false,
                    onDelete: delete
                ) {
                    EmptyView()
                }

                Label("上滑删除", systemImage: "arrow.up")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 16)
            }
            IslandGlow(isOn: glow)
        }
        .preferredColorScheme(.dark)
    }

    private func toggleFavorite(_ item: MediaItem) {
        let newValue = !favorites.contains(item.id)
        if newValue { favorites.insert(item.id) } else { favorites.remove(item.id) }
        Haptics.favorite()
        model.setFavorite(newValue, item: item)
    }

    private func delete(_ item: MediaItem) {
        guard let index = items.firstIndex(of: item) else { return }
        onDelete(item)
        glow = true
        Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            glow = false
        }
        items.remove(at: index)
        if items.isEmpty {
            dismiss()
        } else {
            position = items[min(index, items.count - 1)].id
        }
    }
}
