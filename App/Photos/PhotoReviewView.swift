import ShiGuangCore
import SwiftUI

/// 照片全螢幕瀏覽（對照原版）：
/// - 頂部：返回、組內進度、分享；
/// - 中間：圓角照片卡片，原生分頁左右滑，上滑刪除（照片飛進動態島），雙指捏合「回到那天」；
/// - 底部：收藏、「時間 · 地點 ⓘ」、撤銷。
struct PhotoReviewView: View {
    @Bindable var review: ReviewModel

    @Environment(AppModel.self) private var model
    @AppStorage("hint.deleteSwipe") private var hasSeenDeleteHint = false
    @AppStorage("hint.pageSwipe") private var hasSeenPageHint = false
    @AppStorage("hint.dayTutorial") private var hasSeenDayTutorial = false

    @State private var position: String?
    @State private var glow = false
    @State private var heartBurst = false
    @State private var background = Color(white: 0.12)
    @State private var showUndoHint = false
    @State private var undoHintTask: Task<Void, Never>?
    @State private var currentCardFrame: CGRect = .zero

    // 「回到那天」：在本頁上層展開，照片縮進時間軸
    @State private var timelineAnchor: MediaItem?
    @State private var timelineSource: CGRect?

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
                pager
                bottomBar
            }

            if let anchor = timelineAnchor {
                DayTimelineView(anchor: anchor, sourceFrame: timelineSource) {
                    timelineAnchor = nil
                    review.libraryDidChange()
                }
                .transition(.identity)
                .zIndex(10)
            }

            IslandGlow(isOn: glow)
                .zIndex(11)
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
            MediaInfoSheet(item: item) {
                Task {
                    // 等詳細資訊收起後再展開時間軸
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    openTimeline(item, animatedFromCard: true)
                }
            }
            .environment(model)
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $shareRequest) { request in
            ShareSheet(items: request.items)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $longImageItem) { item in
            LongImageViewer(item: item)
        }
        .onAppear {
            position = current?.id
        }
        .onChange(of: position) { _, id in
            guard let id else { return }
            if id == pagerEndID {
                review.reachEnd()
            } else if id != current?.id {
                hasSeenPageHint = true
                review.move(to: id)
            }
        }
        .onChange(of: current?.id) { _, id in
            // 刪除、撤銷、關閉待刪除清單後，把分頁同步到目前這張
            let target = id ?? (review.session.isFinished ? pagerEndID : nil)
            guard position != target else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { position = target }
        }
        .task(id: current?.id) {
            guard let current else { return }
            background = await ColorExtractor.color(for: current)
        }
        .onChange(of: review.deleteCount) {
            showUndoHintBriefly()
        }
        .onChange(of: review.viewedThisSession) { _, count in
            if count >= 3, !hasSeenDayTutorial, !review.isPresentingPending, infoItem == nil, timelineAnchor == nil {
                showDayTutorial = true
            }
        }
    }

    // MARK: - 頂部

    private var topBar: some View {
        HStack {
            CircleIconButton(systemName: "chevron.left", size: 42) {
                review.requestExit()
            }
            Spacer()
            GroupProgressTrack(progress: review.session.progress)
            Spacer()
            CircleIconButton(systemName: "square.and.arrow.up", size: 42) {
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

    // MARK: - 翻頁

    private var pager: some View {
        SwipePager(
            items: review.session.visibleItems,
            position: $position,
            isActive: timelineAnchor == nil && !review.isPresentingPending,
            onDelete: { item in
                hasSeenDeleteHint = true
                flashGlow()
                if item.id == current?.id {
                    review.deleteCurrent()
                }
            },
            onDoubleTap: { item in
                guard model.settings.doubleTapToFavorite else { return }
                doubleTapFavorite(item)
            },
            onTap: { item in
                if item.isLongImage { longImageItem = item }
            },
            onPinchIn: { item in
                hasSeenDayTutorial = true
                openTimeline(item, animatedFromCard: true)
            },
            onCurrentFrame: { frame in
                currentCardFrame = frame
            }
        ) {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40, weight: .light))
                Text("这一组看完啦")
                    .font(.headline)
            }
            .foregroundStyle(.white.opacity(0.7))
        }
        .overlay {
            if !hasSeenPageHint, current != nil {
                Text("左右滑动切换照片")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 6)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if heartBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.pink)
                    .shadow(radius: 10)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - 底部

    private var bottomBar: some View {
        ZStack {
            HStack {
                let isFavorite = current.map { review.session.isFavorite($0.id) } ?? false
                CircleIconButton(
                    systemName: isFavorite ? "heart.fill" : "heart",
                    size: 48,
                    tint: isFavorite ? .pink : .white
                ) {
                    if let current { review.toggleFavorite(current) }
                }
                .disabled(current == nil)

                Spacer()

                CircleIconButton(systemName: "arrow.uturn.backward", size: 48) {
                    hideUndoHint()
                    review.undo()
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
                    .frame(minHeight: 48)
                    .glassBackground(Capsule())
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

    private func openTimeline(_ item: MediaItem, animatedFromCard: Bool) {
        guard item.creationDate != nil else { return }
        Haptics.tick()
        timelineSource = animatedFromCard && item.id == current?.id ? currentCardFrame : nil
        timelineAnchor = item
    }

    private func flashGlow() {
        glow = true
        Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            glow = false
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
}
