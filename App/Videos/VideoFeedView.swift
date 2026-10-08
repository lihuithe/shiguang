import ShiGuangCore
import SwiftUI

/// 視頻分頁（對照原版）：像短視頻一樣上下滑；右側收藏、分享、刪除、撤銷；左下角時間與地點。
/// 第一次播放前詢問是否要自動播放聲音。
struct VideoFeedView: View {
    @Bindable var review: ReviewModel

    @Environment(AppModel.self) private var model

    @State private var dragY: CGFloat = 0
    @State private var isAnimating = false
    @State private var flyAway = false
    @State private var glow = false
    @State private var soundConfirmed = false
    @State private var showUndoHint = false
    @State private var undoHintTask: Task<Void, Never>?
    @State private var infoItem: MediaItem?
    @State private var dayAnchor: MediaItem?
    @State private var shareRequest: ShareRequest?

    /// 距離螢幕底部的高度，留給浮動 Tab 列
    private let tabBarClearance: CGFloat = 96

    private var current: MediaItem? { review.session.current }

    private var needsSoundPrompt: Bool {
        model.settings.videoSoundPrompt && !soundConfirmed && !model.settings.videoMuted && current != nil
    }

    private var isPlaybackAllowed: Bool {
        !needsSoundPrompt && !review.isPresentingPending && infoItem == nil && dayAnchor == nil && shareRequest == nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if review.hasLoaded, review.session.isEmpty {
                    EmptyCategoryView(title: "视频") { review.reload() }
                } else {
                    pages(size: geo.size)
                }

                if current != nil {
                    chrome
                }

                if needsSoundPrompt {
                    soundPrompt
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                IslandGlow(isOn: glow)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            review.loadIfNeeded()
            review.markCurrentViewed()
        }
        .onChange(of: review.deleteCount) {
            showUndoHintBriefly()
        }
        .sheet(isPresented: $review.isPresentingPending) {
            PendingDeletionSheet(review: review)
        }
        .sheet(item: $infoItem) { item in
            MediaInfoSheet(item: item) {
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    dayAnchor = item
                }
            }
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
    }

    // MARK: - 上下翻頁

    @ViewBuilder
    private func pages(size: CGSize) -> some View {
        ZStack {
            if let next = review.session.next, dragY < 0 || flyAway {
                page(next, size: size, isCurrent: false)
                    .offset(y: flyAway ? 0 : size.height + dragY)
                    .zIndex(0)
            }
            if let current {
                page(current, size: size, isCurrent: true)
                    .scaleEffect(flyAway ? 0.06 : 1)
                    .opacity(flyAway ? 0 : 1)
                    .offset(y: dragY)
                    .zIndex(1)
            }
            if let previous = review.session.previous, dragY > 0 {
                page(previous, size: size, isCurrent: false)
                    .offset(y: -size.height + dragY)
                    .zIndex(2)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(dragGesture(height: size.height))
    }

    private func page(_ item: MediaItem, size: CGSize, isCurrent: Bool) -> some View {
        MediaContentView(
            item: item,
            isActive: isCurrent && isPlaybackAllowed && !isAnimating,
            embedded: true,
            videoMuted: model.settings.videoMuted,
            videoProgressInset: tabBarClearance - 6
        )
        .frame(width: size.width, height: size.height)
        .background(Color.black)
    }

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isAnimating, !needsSoundPrompt, current != nil else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                var dy = value.translation.height
                if dy > 0, !review.session.canGoBack { dy *= 0.25 }
                dragY = dy
            }
            .onEnded { value in
                guard !isAnimating, current != nil else { return }
                let turn = SwipeClassifier.pageTurn(
                    translation: dragY,
                    predictedEnd: value.predictedEndTranslation.height,
                    pageLength: height
                )
                if turn == .forward {
                    commit(to: -height) { review.goForward() }
                } else if turn == .backward, review.session.canGoBack {
                    commit(to: height) { review.goBack() }
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) { dragY = 0 }
                }
            }
    }

    private func commit(to offset: CGFloat, then action: @escaping () -> Void) {
        isAnimating = true
        withAnimation(.easeOut(duration: 0.24)) {
            dragY = offset
        } completion: {
            action()
            resetWithoutAnimation()
            isAnimating = false
        }
    }

    private func resetWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragY = 0
            flyAway = false
        }
    }

    /// 刪除：畫面縮小飛向動態島，下一支接上。
    private func deleteCurrent(height: CGFloat) {
        guard current != nil, !isAnimating else { return }
        isAnimating = true
        let duration = model.settings.deleteAnimationEnabled ? 0.34 : 0.01
        withAnimation(.easeIn(duration: duration)) {
            dragY = 24 - height / 2
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

    // MARK: - 介面元件

    private var chrome: some View {
        GeometryReader { geo in
            ZStack {
                // 右上：待刪除數量
                if !review.session.pendingDeletion.isEmpty {
                    Button {
                        review.isPresentingPending = true
                    } label: {
                        Label("待删除 \(review.session.pendingDeletion.count)", systemImage: "trash")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.red.opacity(0.85), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, geo.safeAreaInsets.top + 8)
                    .padding(.trailing, 16)
                }

                // 右側：收藏、分享、刪除、撤銷
                VStack(spacing: 16) {
                    if let current {
                        let isFavorite = review.session.isFavorite(current.id)
                        CircleIconButton(systemName: isFavorite ? "heart.fill" : "heart", size: 44, tint: isFavorite ? .pink : .white) {
                            review.toggleFavorite(current)
                        }
                        CircleIconButton(systemName: "square.and.arrow.up", size: 44) {
                            Task { shareRequest = await ShareService.request(for: current) }
                        }
                        CircleIconButton(systemName: "trash", size: 44) {
                            deleteCurrent(height: geo.size.height)
                        }
                    }
                    CircleIconButton(systemName: "arrow.uturn.backward", size: 44) {
                        undoHintTask?.cancel()
                        showUndoHint = false
                        withAnimation(.spring(duration: 0.3)) { review.undo() }
                    }
                    .disabled(!review.session.canUndo)
                    .opacity(review.session.canUndo ? 1 : 0.35)
                    .overlay(alignment: .trailing) {
                        if showUndoHint {
                            UndoHintPill()
                                .fixedSize()
                                .offset(x: -56)
                                .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 14)
                .padding(.bottom, tabBarClearance + 70)

                // 左下：時間與地點，點擊看詳細資訊
                if let current {
                    Button {
                        infoItem = current
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            DatePlaceText(item: current, alignment: .leading)
                            Image(systemName: "chevron.up")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .shadow(color: .black.opacity(0.6), radius: 4)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 14)
                    .padding(.bottom, tabBarClearance + 6)
                }
            }
        }
    }

    private var soundPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("播放视频")
                    .font(.headline)
                Text("视频会自动播放声音，要继续吗？")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { soundConfirmed = true }
                } label: {
                    Text("继续")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        soundConfirmed = true
                        model.updateSettings { $0.videoSoundPrompt = false }
                    }
                } label: {
                    Text("不再提示")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.4), radius: 20)
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
}
