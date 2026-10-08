import ShiGuangCore
import SwiftUI

/// 視頻分頁（參考抖音與原版）：
/// - 原生分頁上下滑，畫面只佔 Tab 列以上的區域，底部留給系統 Tab 列；
/// - 輕點暫停 / 播放，長按 2 倍速；
/// - 右側收藏、分享、刪除、撤銷，左下角時間與地點，最底下一條播放進度；
/// - 第一次播放前詢問是否要自動播放聲音。
struct VideoFeedView: View {
    @Bindable var review: ReviewModel

    @Environment(AppModel.self) private var model

    @State private var position: String?
    @State private var flyingID: String?
    @State private var glow = false
    @State private var soundConfirmed = false
    @State private var showUndoHint = false
    @State private var undoHintTask: Task<Void, Never>?
    @State private var infoItem: MediaItem?
    @State private var timelineAnchor: MediaItem?
    @State private var shareRequest: ShareRequest?

    private var current: MediaItem? { review.session.current }

    private var needsSoundPrompt: Bool {
        model.settings.videoSoundPrompt && !soundConfirmed && !model.settings.videoMuted && current != nil
    }

    private var isPlaybackAllowed: Bool {
        !needsSoundPrompt && !review.isPresentingPending && infoItem == nil && timelineAnchor == nil && shareRequest == nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if review.hasLoaded, review.session.isEmpty {
                EmptyCategoryView(title: "视频") { review.reload() }
            } else {
                feed
            }

            // ScrollView 會延伸到 Tab 列後面，下一支剛好排在那裡；
            // 在 Tab 列後方墊一塊純黑底（抖音式），半透明的玻璃 Tab 列就不會透出下一支。
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Color.black
                    .frame(height: 0)
                    .ignoresSafeArea(edges: .bottom)
            }
            .allowsHitTesting(false)

            if needsSoundPrompt {
                soundPrompt
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            IslandGlow(isOn: glow)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            review.loadIfNeeded()
            review.markCurrentViewed()
            position = current?.id
        }
        .onChange(of: position) { _, id in
            guard let id else { return }
            if id == pagerEndID {
                review.reachEnd()
            } else if id != current?.id {
                review.move(to: id)
            }
        }
        .onChange(of: current?.id) { _, id in
            let target = id ?? (review.session.isFinished ? pagerEndID : nil)
            guard position != target else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { position = target }
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
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    timelineAnchor = item
                }
            }
            .environment(model)
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $shareRequest) { request in
            ShareSheet(items: request.items)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $timelineAnchor) { anchor in
            DayTimelineView(anchor: anchor, sourceFrame: nil) {
                timelineAnchor = nil
                review.libraryDidChange()
            }
            .environment(model)
        }
    }

    // MARK: - 信息流

    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(review.session.visibleItems) { item in
                    // 每頁的大小由系統依 ScrollView 實際可見範圍決定，一頁剛好一支，不會露出下一支
                    GeometryReader { geo in
                        page(item, size: geo.size)
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(item.id)
                }
                groupEndPage
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(pagerEndID)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $position)
        .scrollIndicators(.hidden)
        .scrollDisabled(needsSoundPrompt || flyingID != nil)
        // 頂部延伸到狀態列底下，底部停在 Tab 列上方（抖音式）
        .ignoresSafeArea(edges: .top)
    }

    /// 抖音式比例適配：影片比例接近畫面時鋪滿（少量裁切），否則完整顯示並置中
    private func shouldFill(_ item: MediaItem, in size: CGSize) -> Bool {
        guard item.pixelWidth > 0, item.pixelHeight > 0, size.width > 0, size.height > 0 else { return false }
        let videoAspect = CGFloat(item.pixelWidth) / CGFloat(item.pixelHeight)
        let ratio = videoAspect / (size.width / size.height)
        return ratio > 0.78 && ratio < 1.3
    }

    private func page(_ item: MediaItem, size: CGSize) -> some View {
        let isCurrent = item.id == current?.id
        let flying = flyingID == item.id
        return ZStack {
            MediaContentView(
                item: item,
                isActive: isCurrent && isPlaybackAllowed && flyingID == nil,
                embedded: true,
                videoMuted: model.settings.videoMuted,
                videoProgressInset: 0,
                videoFill: shouldFill(item, in: size)
            )
            .frame(width: size.width, height: size.height)
            .clipped()
            .scaleEffect(flying ? 0.06 : 1)
            .offset(y: flying ? 24 - size.height / 2 : 0)
            .opacity(flying ? 0 : 1)

            if isCurrent, !flying {
                overlay(for: item, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
    }

    private var groupEndPage: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
            Text("这一组看完啦")
                .font(.headline)
        }
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - 介面元件

    private func overlay(for item: MediaItem, size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            // 底部漸層，讓白色文字在亮畫面上也看得清
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                .frame(height: 220)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

            HStack(alignment: .bottom) {
                Button {
                    infoItem = item
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        DatePlaceText(item: item, alignment: .leading)
                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .shadow(color: .black.opacity(0.6), radius: 4)
                }
                .buttonStyle(.plain)

                Spacer()

                actionColumn(for: item, height: size.height)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private func actionColumn(for item: MediaItem, height: CGFloat) -> some View {
        let isFavorite = review.session.isFavorite(item.id)
        return VStack(spacing: 16) {
            CircleIconButton(systemName: isFavorite ? "heart.fill" : "heart", size: 46, tint: isFavorite ? .pink : .white) {
                review.toggleFavorite(item)
            }
            CircleIconButton(systemName: "square.and.arrow.up", size: 46) {
                Task { shareRequest = await ShareService.request(for: item) }
            }
            CircleIconButton(systemName: "trash", size: 46) {
                delete(item)
            }
            CircleIconButton(systemName: "arrow.uturn.backward", size: 46) {
                undoHintTask?.cancel()
                showUndoHint = false
                review.undo()
            }
            .disabled(!review.session.canUndo)
            .opacity(review.session.canUndo ? 1 : 0.35)
            .overlay(alignment: .trailing) {
                if showUndoHint {
                    UndoHintPill()
                        .fixedSize()
                        .offset(x: -58)
                        .transition(.opacity)
                }
            }
        }
    }

    /// 刪除：畫面縮小飛向動態島，下一支接上；看完一組時統一確認。
    private func delete(_ item: MediaItem) {
        guard flyingID == nil else { return }
        let duration = model.settings.deleteAnimationEnabled ? 0.32 : 0.01
        withAnimation(.easeIn(duration: duration)) {
            flyingID = item.id
        } completion: {
            glow = true
            review.deleteCurrent()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { flyingID = nil }
            Task {
                try? await Task.sleep(nanoseconds: 260_000_000)
                glow = false
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
                        .glassBackground(Capsule())
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
                        .glassBackground(Capsule())
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: 300)
        .glassBackground(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
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
