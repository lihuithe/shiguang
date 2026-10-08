import ShiGuangCore
import SwiftUI

/// 首頁：全螢幕隨機瀏覽。上滑刪除、下滑收藏、左滑下一張、右滑上一張、雙擊收藏、雙指捏合「回到那天」。
struct BrowserView: View {
    @Bindable var vm: BrowserViewModel

    @Environment(AppModel.self) private var model
    @AppStorage("hasSeenGestureGuide") private var hasSeenGestureGuide = false

    @State private var dragOffset: CGSize = .zero
    @State private var isAnimatingOut = false
    @State private var pinchScale: CGFloat = 1
    @State private var isPinching = false
    @State private var heartBurst = false

    @State private var dayAnchor: MediaItem?
    @State private var longImageItem: MediaItem?
    @State private var showStats = false
    @State private var showSettings = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                switch vm.phase {
                case .loading:
                    ProgressView().tint(.white)
                case .empty:
                    EmptyCategoryView(category: vm.category) {
                        vm.startNewGroup()
                    }
                case .browsing:
                    if let item = vm.session.current {
                        card(for: item, in: proxy.size)
                    }
                case .review:
                    GroupReviewView(vm: vm)
                        .transition(.opacity)
                }

                VStack(spacing: 0) {
                    topBar
                    if vm.didRecycle, vm.phase == .browsing {
                        recycleBanner
                    }
                    Spacer()
                    if vm.phase == .browsing, let item = vm.session.current {
                        bottomBar(for: item, size: proxy.size)
                    }
                }

                if !hasSeenGestureGuide, vm.phase == .browsing {
                    GestureGuideView { hasSeenGestureGuide = true }
                        .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .fullScreenCover(item: $dayAnchor) { anchor in
            DayView(anchor: anchor)
                .environment(model)
        }
        .fullScreenCover(item: $longImageItem) { item in
            LongImageViewer(item: item)
        }
        .sheet(isPresented: $showStats) {
            StatsView().environment(model)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onHistoryReset: { vm.categoryDidChange() })
                .environment(model)
        }
        .alert("出错了", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .onChange(of: dayAnchor) { _, anchor in
            // 從「回到那天」回來後，刪掉的照片可能就在本組裡
            if anchor == nil { vm.libraryDidChange() }
        }
    }

    // MARK: - 卡片

    @ViewBuilder
    private func card(for item: MediaItem, in size: CGSize) -> some View {
        let marked = vm.session.isMarkedForDeletion(item.id)
        ZStack {
            MediaContentView(item: item, isActive: !isAnimatingOut && dayAnchor == nil)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .identity))
                .overlay {
                    if marked {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.9), lineWidth: 4)
                            .padding(8)
                    }
                }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(cardScale(in: size))
        .rotationEffect(.degrees(Double(dragOffset.width) / 30))
        .offset(dragOffset)
        .opacity(cardOpacity(in: size))
        .overlay { dragHint(in: size) }
        .overlay {
            if heartBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.pink)
                    .shadow(radius: 10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if marked {
                Button {
                    vm.toggleDeletion(item)
                } label: {
                    Label("已标记删除 · 点击取消", systemImage: "trash.slash")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.85), in: Capsule())
                }
                .padding(.top, 150)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture(in: size))
        .simultaneousGesture(pinchGesture(for: item))
        .onTapGesture(count: 2) {
            guard model.settings.doubleTapToFavorite else { return }
            doubleTapFavorite(item)
        }
    }

    private func cardScale(in size: CGSize) -> CGFloat {
        let pinch = min(max(pinchScale, 0.6), 1.15)
        guard dragOffset.height < 0 else { return pinch }
        // 上滑時逐漸縮小，像被丟進垃圾桶
        let progress = min(-dragOffset.height / size.height, 1)
        return pinch * (1 - progress * 0.35)
    }

    private func cardOpacity(in size: CGSize) -> Double {
        let distance = max(abs(dragOffset.width) / size.width, abs(dragOffset.height) / size.height)
        return Double(1 - min(max(distance - 0.4, 0), 0.6))
    }

    @ViewBuilder
    private func dragHint(in size: CGSize) -> some View {
        let action = SwipeClassifier.classify(
            translationX: dragOffset.width, translationY: dragOffset.height,
            distanceThreshold: 40, flickThreshold: .infinity
        )
        let strength = min(max(abs(dragOffset.width), abs(dragOffset.height)) / 120, 1)
        if !isAnimatingOut, action != .none {
            let style = hintStyle(for: action)
            VStack(spacing: 8) {
                Image(systemName: style.icon).font(.system(size: 44, weight: .semibold))
                Text(style.title).font(.headline)
            }
            .foregroundStyle(style.color)
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .opacity(strength)
            .allowsHitTesting(false)
        }
    }

    private func hintStyle(for action: SwipeAction) -> (title: String, icon: String, color: Color) {
        switch action {
        case .delete: return ("删除", "trash.fill", .red)
        case .favorite: return ("收藏", "heart.fill", .pink)
        case .next: return ("下一张", "arrow.left", .white)
        case .previous: return (vm.session.canGoBack ? "上一张" : "已是第一张", "arrow.right", .white)
        case .none: return ("", "", .clear)
        }
    }

    // MARK: - 手勢

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard !isPinching, !isAnimatingOut else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isPinching, !isAnimatingOut else {
                    withAnimation(.spring(duration: 0.3)) { dragOffset = .zero }
                    return
                }
                let action = SwipeClassifier.classify(
                    translationX: value.translation.width,
                    translationY: value.translation.height,
                    predictedEndX: value.predictedEndTranslation.width,
                    predictedEndY: value.predictedEndTranslation.height
                )
                commit(action, size: size)
            }
    }

    private func pinchGesture(for item: MediaItem) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                isPinching = true
                dragOffset = .zero
                pinchScale = value.magnification
            }
            .onEnded { value in
                let open = SwipeClassifier.shouldOpenDay(pinchScale: value.magnification)
                withAnimation(.spring(duration: 0.3)) { pinchScale = 1 }
                isPinching = false
                if open {
                    Haptics.tick()
                    dayAnchor = item
                }
            }
    }

    /// 執行滑動動作：先讓卡片飛出，再切換到下一張。
    private func commit(_ action: SwipeAction, size: CGSize) {
        let canMove = action != .none && !(action == .previous && !vm.session.canGoBack)
        guard canMove else {
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { dragOffset = .zero }
            return
        }

        let target: CGSize
        switch action {
        case .delete: target = CGSize(width: dragOffset.width * 0.3, height: -size.height * 0.9)
        case .favorite: target = CGSize(width: 0, height: size.height)
        case .next: target = CGSize(width: -size.width * 1.3, height: dragOffset.height)
        case .previous: target = CGSize(width: size.width * 1.3, height: dragOffset.height)
        case .none: target = .zero
        }

        let animate = action != .delete || model.settings.deleteAnimationEnabled
        guard animate else {
            dragOffset = .zero
            vm.perform(action)
            return
        }

        isAnimatingOut = true
        withAnimation(.easeIn(duration: action == .delete ? 0.28 : 0.2)) {
            dragOffset = target
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dragOffset = .zero }
            withAnimation(.easeOut(duration: 0.18)) {
                vm.perform(action)
            }
            isAnimatingOut = false
        }
    }

    private func doubleTapFavorite(_ item: MediaItem) {
        vm.toggleFavorite(item)
        guard vm.session.isFavorite(item.id) else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.5)) { heartBurst = true }
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(.easeOut(duration: 0.2)) { heartBurst = false }
        }
    }

    // MARK: - 上下工具列

    private var topBar: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("分类", selection: Binding(
                    get: { vm.category },
                    set: { vm.switchCategory($0) }
                )) {
                    ForEach(MediaCategory.allCases) { category in
                        Label(category.title, systemImage: category.systemImage).tag(category)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: vm.category.systemImage)
                    Text(vm.category.title)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }

            if model.settings.demoMode {
                Text("演示")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow, in: Capsule())
            }

            Spacer()

            if vm.phase == .browsing {
                Text(vm.session.progressText)
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            CircleIconButton(systemName: "chart.bar.fill") { showStats = true }
            CircleIconButton(systemName: "gearshape.fill") { showSettings = true }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var recycleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            Text("这个分类都看过啦，正在重温最早看过的内容")
                .font(.footnote)
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            Button("重新开始") { vm.resetCategoryHistory() }
                .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func bottomBar(for item: MediaItem, size: CGSize) -> some View {
        VStack(spacing: 14) {
            if model.settings.showDate {
                Button {
                    dayAnchor = item
                } label: {
                    HStack(spacing: 6) {
                        Text(DateDisplay.format(item.creationDate, style: model.settings.dateStyle, calendar: model.calendar))
                        if item.creationDate != nil {
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                }
                .disabled(item.creationDate == nil)
            }

            HStack(spacing: 18) {
                CircleIconButton(systemName: "arrow.uturn.backward", size: 46) {
                    withAnimation(.easeOut(duration: 0.18)) { vm.undo() }
                }
                .disabled(!vm.session.canUndo)
                .opacity(vm.session.canUndo ? 1 : 0.4)

                CircleIconButton(systemName: "calendar", size: 46) {
                    dayAnchor = item
                }
                .disabled(item.creationDate == nil)

                CircleIconButton(systemName: "trash.fill", size: 62, tint: .red) {
                    commit(.delete, size: size)
                }

                CircleIconButton(
                    systemName: vm.session.isFavorite(item.id) ? "heart.fill" : "heart",
                    size: 46,
                    tint: vm.session.isFavorite(item.id) ? .pink : .white
                ) {
                    vm.toggleFavorite(item)
                }

                if item.isLongImage {
                    CircleIconButton(systemName: "arrow.up.and.down.text.horizontal", size: 46) {
                        longImageItem = item
                    }
                } else {
                    CircleIconButton(systemName: "arrow.left", size: 46) {
                        commit(.next, size: size)
                    }
                }
            }
        }
        .padding(.bottom, 20)
    }
}

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 38
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct EmptyCategoryView: View {
    let category: MediaCategory
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: category.systemImage)
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.5))
            Text("「\(category.title)」里还没有内容")
                .font(.headline)
                .foregroundStyle(.white)
            Text("换个分类看看，或者在设置里管理可访问的照片。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("重新加载", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

/// 首次使用時的手勢說明。
struct GestureGuideView: View {
    let dismiss: () -> Void

    private let rows: [(String, String)] = [
        ("arrow.up", "上滑：标记删除（看完一组再统一确认）"),
        ("arrow.down", "下滑：收藏并看下一张"),
        ("arrow.left", "左滑：保留，看下一张"),
        ("arrow.right", "右滑：回到上一张"),
        ("hand.tap", "双击：收藏"),
        ("arrow.down.right.and.arrow.up.left", "双指捏合：回到那天，看看当天还拍了什么"),
        ("hand.point.up.left", "长按视频：2 倍速播放"),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("像刷短视频一样回顾照片")
                    .font(.title2.weight(.bold))
                Text("每次随机抽一组，看过的照片很久都不会再出现。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                ForEach(rows, id: \.1) { icon, text in
                    HStack(spacing: 14) {
                        Image(systemName: icon)
                            .frame(width: 28)
                            .foregroundStyle(Color.accentColor)
                        Text(text)
                    }
                    .font(.body)
                }
                Button(action: dismiss) {
                    Text("开始回顾")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .foregroundStyle(.white)
            .padding(28)
        }
        .onTapGesture(perform: dismiss)
    }
}
