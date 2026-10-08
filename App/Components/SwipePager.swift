import ShiGuangCore
import SwiftUI

/// 分頁尾端的「看完一組」頁面 ID
let pagerEndID = "__group_end__"

/// 左右翻頁的照片瀏覽器：
/// - 翻頁交給原生分頁 ScrollView（流暢、可快速輕掃，相鄰頁預先載入）；
/// - 上滑刪除疊加在目前這張上：手指往上拖時卡片跟著縮小，鬆手後飛向動態島；
/// - 可選的結尾頁，滑到結尾表示看完一組。
struct SwipePager<EndPage: View>: View {
    let items: [MediaItem]
    /// 目前停留的項目 ID（或 pagerEndID）
    @Binding var position: String?
    var isActive = true
    var showsEndPage = true
    /// 刪除動畫結束後呼叫，呼叫方負責把項目移出 items
    let onDelete: (MediaItem) -> Void
    var onDoubleTap: ((MediaItem) -> Void)? = nil
    var onTap: ((MediaItem) -> Void)? = nil
    /// 雙指捏合縮小
    var onPinchIn: ((MediaItem) -> Void)? = nil
    /// 讓呼叫方知道目前卡片在螢幕上的位置（「回到那天」的縮放過場用）
    var onCurrentFrame: ((CGRect) -> Void)? = nil
    @ViewBuilder var endPage: () -> EndPage

    @Environment(AppModel.self) private var model
    @State private var dragY: CGFloat = 0
    @State private var flyingID: String?
    @State private var pinchScale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let frame = geo.frame(in: .global)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in
                        page(item, size: size, pagerFrame: frame)
                            .frame(width: size.width, height: size.height)
                            .id(item.id)
                    }
                    if showsEndPage {
                        endPage()
                            .frame(width: size.width, height: size.height)
                            .id(pagerEndID)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $position)
            .scrollIndicators(.hidden)
            .scrollDisabled(dragY != 0 || flyingID != nil)
            .onChange(of: position, initial: true) {
                reportFrame(size: size, pagerFrame: frame)
            }
            .onChange(of: frame) {
                reportFrame(size: size, pagerFrame: frame)
            }
        }
    }

    private func reportFrame(size: CGSize, pagerFrame: CGRect) {
        guard let onCurrentFrame, let item = items.first(where: { $0.id == position }) else { return }
        let card = ReviewCard.fittedSize(for: item, in: size)
        onCurrentFrame(CGRect(
            x: pagerFrame.midX - card.width / 2,
            y: pagerFrame.midY - card.height / 2,
            width: card.width,
            height: card.height
        ))
    }

    // MARK: - 單頁

    private func page(_ item: MediaItem, size: CGSize, pagerFrame: CGRect) -> some View {
        let isCurrent = item.id == position
        let flying = flyingID == item.id
        let progress: CGFloat = isCurrent ? CGFloat(SwipeClassifier.deleteProgress(translationY: dragY, height: size.height)) : 0
        let pinch: CGFloat = isCurrent ? min(max(pinchScale, 0.6), 1.1) : 1
        let scale: CGFloat = flying ? 0.06 : (1 - progress * 0.3) * pinch

        return ReviewCard(
            item: item,
            available: size,
            isActive: isActive && isCurrent && dragY == 0 && flyingID == nil
        )
        .scaleEffect(scale)
        .opacity(flying ? 0 : 1)
        .offset(y: isCurrent ? dragY : 0)
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .scaleEffect(1 - abs(phase.value) * 0.08)
                .opacity(1 - abs(phase.value) * 0.35)
        }
        .contentShape(Rectangle())
        // 上滑刪除只掛在目前這張，且只在明確往上拖時才接手，左右滑交給 ScrollView
        .gesture(deleteGesture(item, size: size, pagerFrame: pagerFrame))
        .simultaneousGesture(pinchGesture(item), including: isCurrent ? .all : .subviews)
        .onTapGesture(count: 2) { onDoubleTap?(item) }
        .onTapGesture { onTap?(item) }
    }

    // MARK: - 上滑刪除

    private func deleteGesture(_ item: MediaItem, size: CGSize, pagerFrame: CGRect) -> UpwardPanGesture {
        UpwardPanGesture { translationY in
            guard flyingID == nil, item.id == position else { return }
            dragY = translationY < 0 ? translationY : translationY * 0.15
        } onEnded: { translationY, predictedEndY in
            guard flyingID == nil, item.id == position else { return }
            let delete = SwipeClassifier.shouldDelete(
                translationY: translationY,
                predictedEndY: predictedEndY,
                height: size.height
            )
            if delete {
                flyAway(item, cardCenterY: pagerFrame.midY)
            } else {
                withAnimation(.spring(duration: 0.35, bounce: 0.25)) { dragY = 0 }
            }
        }
    }

    /// 照片縮小飛向動態島
    private func flyAway(_ item: MediaItem, cardCenterY: CGFloat) {
        let duration = model.settings.deleteAnimationEnabled ? 0.32 : 0.01
        withAnimation(.easeIn(duration: duration)) {
            dragY = 24 - cardCenterY
            flyingID = item.id
        } completion: {
            onDelete(item)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragY = 0
                flyingID = nil
            }
        }
    }

    // MARK: - 捏合

    private func pinchGesture(_ item: MediaItem) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard onPinchIn != nil, item.id == position, flyingID == nil else { return }
                pinchScale = value.magnification
            }
            .onEnded { value in
                guard onPinchIn != nil else { return }
                let open = SwipeClassifier.shouldOpenDay(pinchScale: value.magnification)
                if open {
                    onPinchIn?(item)
                    pinchScale = 1
                } else {
                    withAnimation(.spring(duration: 0.3)) { pinchScale = 1 }
                }
            }
    }
}

/// 瀏覽頁的照片卡片：按照片比例縮放到可用區域內，圓角；實況照片左上角有「实况 ⌄」選單。
struct ReviewCard: View {
    let item: MediaItem
    let available: CGSize
    let isActive: Bool

    @Environment(AppModel.self) private var model

    static func fittedSize(for item: MediaItem, in available: CGSize) -> CGSize {
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
        let cardSize = Self.fittedSize(for: item, in: available)
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
            .glassBackground(Capsule(), interactive: false)
        }
    }
}
