import ShiGuangCore
import SwiftUI

/// 照片全螢幕瀏覽（對照原版）：
/// - 頂部：返回、組內進度、分享；
/// - 中間：圓角照片卡片，左右滑切換，上滑刪除（照片飛進動態島），雙指捏合「回到那天」；
/// - 底部：收藏、「時間 · 地點 ⓘ」、撤銷。
struct PhotoReviewView: View {
    @Bindable var review: ReviewModel

    @Environment(AppModel.self) private var model
    @AppStorage("hint.deleteSwipe") private var hasSeenDeleteHint = false
    @AppStorage("hint.pageSwipe") private var hasSeenPageHint = false
    @AppStorage("hint.dayTutorial") private var hasSeenDayTutorial = false

    // 拖曳與動畫
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var axis: DragAxis?
    @State private var isAnimating = false
    @State private var flyAway = false
    @State private var glow = false
    @State private var pinchScale: CGFloat = 1
    @State private var isPinching = false
    @State private var heartBurst = false

    // 介面狀態
    @State private var background = Color(white: 0.12)
    @State private var showUndoHint = false
    @State private var undoHintTask: Task<Void, Never>?
    @State private var dayAnchor: MediaItem?
    @State private var infoItem: MediaItem?
    @State private var longImageItem: MediaItem?
    @State private var shareRequest: ShareRequest?
    @State private var showDayTutorial = false

    private var current: MediaItem? { review.session.current }

    var body: some View {
        ZStack {
            LinearGradient(colors: [background, background.opacity(0.6), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: background)

            VStack(spacing: 0) {
                topBar
                deleteHint
                    .frame(height: 36)
                GeometryReader { geo in
                    pager(in: geo)
                }
                bottomBar
            }

            IslandGlow(isOn: glow)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $review.isPresentingPending) {
            PendingDeletionSheet(review: review)
        }
        .sheet(isPresented: $showDayTutorial) {
            DayTutorialSheet(item: current) {
                hasSeenDayTutorial = true
                showDayTutorial = false
            }
            .presentationDetents([.height(440)])
        }
        .sheet(item: $infoItem) { item in
            MediaInfoSheet(item: item) { openDay(item, afterSheet: true) }
                .environment(model)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $shareRequest) { request in
            ShareSheet(items: request.items)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $dayAnchor) { anchor in
            DayView(anchor: anchor)
                .environment(model)
        }
        .fullScreenCover(item: $longImageItem) { item in
            LongImageViewer(item: item)
        }
        .task(id: current?.id) {
            guard let current else { return }
            background = await ColorExtractor.color(for: current)
        }
        .onChange(of: review.deleteCount) {
            showUndoHintBriefly()
        }
        .onChange(of: review.viewedThisSession) { _, count in
            if count >= 3, !hasSeenDayTutorial, !review.isPresentingPending, infoItem == nil {
                showDayTutorial = true
            }
        }
        .onChange(of: dayAnchor) { _, anchor in
            // 從「回到那天」回來後，刪掉的照片可能就在本組裡
            if anchor == nil { review.libraryDidChange() }
        }
    }

    // MARK: - 頂部

    private var topBar: some View {
        HStack {
            CircleIconButton(systemName: "chevron.left", size: 40) {
                review.requestExit()
            }
            Spacer()
            GroupProgressTrack(progress: review.session.progress)
            Spacer()
            CircleIconButton(systemName: "square.and.arrow.up", size: 40) {
                share(current)
            }
            .disabled(current == nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var deleteHint: some View {
        if !hasSeenDeleteHint {
            VStack(spacing: 0) {
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 18, weight: .semibold))
                Text("上滑删除")
                    .font(.footnote.weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.85))
            .phaseAnimator([CGFloat(0), CGFloat(-4)]) { view, offset in
                view.offset(y: offset)
            } animation: { _ in .easeInOut(duration: 0.8) }
        }
    }

    // MARK: - 卡片翻頁

    private enum Role {
        case previous, current, next
    }

    @ViewBuilder
    private func pager(in geo: GeometryProxy) -> some View {
        let size = geo.size
        let frame = geo.frame(in: .global)
        ZStack {
            if let next = review.session.next, dragX < 0 || dragY < 0 || flyAway {
                card(next, role: .next, size: size)
                    .zIndex(0)
            }
            if let current {
                card(current, role: .current, size: size)
                    .zIndex(1)
            }
            if let previous = review.session.previous, dragX > 0 {
                card(previous, role: .previous, size: size)
                    .zIndex(2)
            }
            if !hasSeenPageHint, current != nil, !isAnimating, dragX == 0, dragY == 0 {
                Text("左右滑动切换照片")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 6)
                    .allowsHitTesting(false)
                    .zIndex(3)
            }
            if heartBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.pink)
                    .shadow(radius: 10)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(4)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(dragGesture(size: size, cardCenterY: frame.midY))
        .simultaneousGesture(pinchGesture)
        .gesture(tapGesture)
    }

    private func card(_ item: MediaItem, role: Role, size: CGSize) -> some View {
        let width = max(size.width, 1)
        let pageProgress = min(abs(dragX) / width, 1)
        let deleteProgress = SwipeClassifier.deleteProgress(translationY: dragY, height: size.height)

        var offset = CGSize.zero
        var scale: CGFloat = 1
        var opacity: Double = 1
        var blur: CGFloat = 0

        switch role {
        case .current:
            if dragX < 0 { offset.width = dragX }
            offset.height = dragY
            if dragX > 0 {
                // 上一張從左邊滑進來蓋住目前這張
                opacity = 1 - pageProgress * 0.6
                blur = pageProgress * 8
                scale = 1 - pageProgress * 0.06
            }
            if flyAway {
                scale = 0.06
                opacity = 0
            } else if dragY < 0 {
                scale = 1 - deleteProgress * 0.3
            }
            scale *= min(max(pinchScale, 0.6), 1.1)
        case .next:
            let reveal = flyAway ? 1 : max(pageProgress, deleteProgress)
            opacity = reveal
            scale = 0.9 + 0.1 * reveal
            blur = (1 - reveal) * 10
        case .previous:
            offset.width = -width + dragX
        }

        return ReviewCard(item: item, available: size, isActive: role == .current && !isAnimating && dragY == 0)
            .scaleEffect(scale)
            .blur(radius: blur)
            .opacity(opacity)
            .offset(offset)
            .allowsHitTesting(role == .current)
    }

    // MARK: - 手勢

    private func dragGesture(size: CGSize, cardCenterY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isAnimating, !isPinching, current != nil else { return }
                if axis == nil {
                    axis = SwipeClassifier.lockAxis(translationX: value.translation.width, translationY: value.translation.height)
                }
                switch axis {
                case .horizontal:
                    var dx = value.translation.width
                    if dx > 0, !review.session.canGoBack { dx *= 0.25 }
                    dragX = dx
                case .vertical:
                    let dy = value.translation.height
                    dragY = dy < 0 ? dy : dy * 0.15
                case nil:
                    break
                }
            }
            .onEnded { value in
                let lockedAxis = axis
                axis = nil
                guard !isAnimating, !isPinching, current != nil else {
                    springBack()
                    return
                }
                switch lockedAxis {
                case .horizontal:
                    let turn = SwipeClassifier.pageTurn(
                        translation: value.translation.width,
                        predictedEnd: value.predictedEndTranslation.width,
                        pageLength: size.width
                    )
                    if turn == .forward {
                        commitForward(width: size.width)
                    } else if turn == .backward, review.session.canGoBack {
                        commitBackward(width: size.width)
                    } else {
                        springBack()
                    }
                case .vertical:
                    if SwipeClassifier.shouldDelete(
                        translationY: value.translation.height,
                        predictedEndY: value.predictedEndTranslation.height,
                        height: size.height
                    ) {
                        commitDelete(cardCenterY: cardCenterY)
                    } else {
                        springBack()
                    }
                case nil:
                    springBack()
                }
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard !isAnimating, current != nil else { return }
                isPinching = true
                dragX = 0
                dragY = 0
                pinchScale = value.magnification
            }
            .onEnded { value in
                let open = SwipeClassifier.shouldOpenDay(pinchScale: value.magnification)
                withAnimation(.spring(duration: 0.3)) { pinchScale = 1 }
                isPinching = false
                if open, let current {
                    hasSeenDayTutorial = true
                    openDay(current, afterSheet: false)
                }
            }
    }

    private var tapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                guard let current, model.settings.doubleTapToFavorite else { return }
                doubleTapFavorite(current)
            }
            .exclusively(before: TapGesture().onEnded {
                if let current, current.isLongImage {
                    longImageItem = current
                }
            })
    }

    // MARK: - 動畫提交

    private func springBack() {
        withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
            dragX = 0
            dragY = 0
        }
    }

    private func resetWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragX = 0
            dragY = 0
            flyAway = false
        }
    }

    private func commitForward(width: CGFloat) {
        hasSeenPageHint = true
        isAnimating = true
        Haptics.tick()
        withAnimation(.easeOut(duration: 0.22)) {
            dragX = -width
        } completion: {
            review.goForward()
            resetWithoutAnimation()
            isAnimating = false
        }
    }

    private func commitBackward(width: CGFloat) {
        hasSeenPageHint = true
        isAnimating = true
        Haptics.tick()
        withAnimation(.easeOut(duration: 0.22)) {
            dragX = width
        } completion: {
            review.goBack()
            resetWithoutAnimation()
            isAnimating = false
        }
    }

    /// 上滑刪除：照片縮小飛向動態島，動態島閃紅光，下一張接上。
    private func commitDelete(cardCenterY: CGFloat) {
        hasSeenDeleteHint = true
        isAnimating = true
        let islandY: CGFloat = 24
        let duration = model.settings.deleteAnimationEnabled ? 0.34 : 0.01
        withAnimation(.easeIn(duration: duration)) {
            dragY = islandY - cardCenterY
            flyAway = true
        } completion: {
            glow = true
            review.deleteCurrent()
            resetWithoutAnimation()
            isAnimating = false
            Task {
                try? await Task.sleep(nanoseconds: 260_000_000)
                glow = false
            }
        }
    }

    private func doubleTapFavorite(_ item: MediaItem) {
        review.toggleFavorite(item)
        guard review.session.isFavorite(item.id) else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.5)) { heartBurst = true }
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(.easeOut(duration: 0.2)) { heartBurst = false }
        }
    }

    // MARK: - 底部

    private var bottomBar: some View {
        ZStack {
            HStack {
                let isFavorite = current.map { review.session.isFavorite($0.id) } ?? false
                CircleIconButton(
                    systemName: isFavorite ? "heart.fill" : "heart",
                    size: 46,
                    tint: isFavorite ? .pink : .white
                ) {
                    if let current { review.toggleFavorite(current) }
                }
                .disabled(current == nil)

                Spacer()

                CircleIconButton(systemName: "arrow.uturn.backward", size: 46) {
                    withAnimation(.spring(duration: 0.3)) { review.undo() }
                    hideUndoHint()
                }
                .disabled(!review.session.canUndo)
                .opacity(review.session.canUndo ? 1 : 0.35)
                .overlay(alignment: .topTrailing) {
                    if showUndoHint {
                        UndoHintPill()
                            .fixedSize()
                            .offset(y: -48)
                            .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
                    }
                }
            }

            if let current {
                Button {
                    infoItem = current
                } label: {
                    HStack(spacing: 10) {
                        DatePlaceText(item: current)
                        Image(systemName: "info.circle.fill")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .frame(minHeight: 46)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 220)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - 輔助

    private func showUndoHintBriefly() {
        undoHintTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { showUndoHint = true }
        undoHintTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { showUndoHint = false }
        }
    }

    private func hideUndoHint() {
        undoHintTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { showUndoHint = false }
    }

    private func share(_ item: MediaItem?) {
        guard let item else { return }
        Task { shareRequest = await ShareService.request(for: item) }
    }

    private func openDay(_ item: MediaItem, afterSheet: Bool) {
        guard item.creationDate != nil else { return }
        Haptics.tick()
        if afterSheet {
            // 等詳細資訊彈窗收起後再全螢幕打開，避免轉場衝突
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                dayAnchor = item
            }
        } else {
            dayAnchor = item
        }
    }
}

/// 瀏覽頁的照片卡片：按照片比例縮放到可用區域內，圓角；實況照片左上角有「实况 ⌄」選單。
struct ReviewCard: View {
    let item: MediaItem
    let available: CGSize
    let isActive: Bool

    @Environment(AppModel.self) private var model

    private var cardSize: CGSize {
        let maxWidth = max(available.width - 24, 1)
        let maxHeight = max(available.height - 16, 1)
        let aspect: CGFloat = item.pixelWidth > 0 && item.pixelHeight > 0
            ? CGFloat(item.pixelWidth) / CGFloat(item.pixelHeight)
            : 0.75
        var width = maxWidth
        var height = width / aspect
        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }

    var body: some View {
        MediaContentView(item: item, isActive: isActive, embedded: true)
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topLeading) {
                if item.isLivePhoto {
                    liveMenu.padding(8)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            .frame(width: available.width, height: available.height)
    }

    private var liveMenu: some View {
        Menu {
            Toggle("自动播放", isOn: model.binding(\.livePhotoAutoplay))
            Toggle("静音", isOn: model.binding(\.livePhotoMuted))
        } label: {
            HStack(spacing: 3) {
                Image(systemName: model.settings.livePhotoAutoplay ? "livephoto" : "livephoto.slash")
                Text("实况")
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
        }
    }
}
