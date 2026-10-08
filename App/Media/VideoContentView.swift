import AVFoundation
import Photos
import ShiGuangCore
import SwiftUI

/// 影片：自動循環播放、輕點暫停 / 播放、長按 2 倍速、拖動底部進度條跳轉。
struct VideoContentView: View {
    let item: MediaItem
    let isActive: Bool
    /// 顯示時長標記與靜音按鈕；嵌在信息流時由外層提供控制元件
    var showsChrome = true
    /// 由外部控制是否靜音；nil 表示用設定值，並允許使用者用按鈕切換
    var mutedOverride: Bool? = nil
    /// 進度條距離底部的距離
    var progressInset: CGFloat = 104
    /// 鋪滿外框（裁切）；否則完整顯示並置中
    var fill = false

    @Environment(AppModel.self) private var model
    @State private var player = AVPlayer()
    @State private var isReady = false
    @State private var downloadProgress: Double = 0
    @State private var playbackProgress: Double = 0
    @State private var isFastForwarding = false
    @State private var isMuted = false
    @State private var timeObserver: Any?
    @State private var loopObserver: NSObjectProtocol?
    /// 使用者輕點暫停；換到別支影片或重新出現時恢復
    @State private var isPausedByUser = false

    // 拖動進度
    @State private var isScrubbing = false
    @State private var scrubFraction: Double = 0
    @State private var wasPlayingBeforeScrub = false
    @State private var isSeeking = false
    @State private var pendingSeek: Double?

    /// 以播放器回報的長度為準，還沒載入時用相簿記錄的長度
    private var duration: Double {
        let seconds = player.currentItem?.duration.seconds ?? .nan
        return seconds.isFinite && seconds > 0 ? seconds : max(item.duration, 0.1)
    }

    var body: some View {
        ZStack {
            PhotoContentView(item: item, hdr: false, fill: fill)
                .opacity(isReady ? 0 : 1)

            PlayerLayerView(player: player, hdr: model.effectiveHDR, fill: fill)
                .opacity(isReady ? 1 : 0)

            VStack {
                if showsChrome {
                    HStack {
                        MediaBadge(title: DurationText.format(item.duration), systemImage: "video.fill")
                        Spacer()
                        Button {
                            isMuted.toggle()
                            player.isMuted = isMuted
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.footnote)
                                .foregroundStyle(.white)
                                .padding(8)
                                .glassBackground(Circle())
                        }
                    }
                    .padding(.top, 110)
                    .padding(.horizontal, 16)
                }

                Spacer()

                if isScrubbing {
                    // 拖動進度時畫面中間偏下顯示「目前 / 總長」
                    HStack(spacing: 6) {
                        Text(DurationText.format(scrubFraction * duration))
                            .foregroundStyle(.white)
                        Text("/")
                            .foregroundStyle(.white.opacity(0.5))
                        Text(DurationText.format(duration))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .shadow(color: .black.opacity(0.6), radius: 8)
                    .padding(.bottom, 40)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }

                if isFastForwarding {
                    Label("2× 快进中", systemImage: "forward.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassBackground(Capsule(), interactive: false)
                        .padding(.bottom, 24)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .allowsHitTesting(false)
                }

                VideoScrubber(
                    loaded: isReady ? 1 : downloadProgress,
                    played: isScrubbing ? scrubFraction : playbackProgress,
                    isScrubbing: isScrubbing,
                    isEnabled: isReady && isActive,
                    onChanged: scrub(to:),
                    onEnded: endScrub(at:)
                )
                .padding(.horizontal, showsChrome ? 16 : 0)
                .padding(.bottom, progressInset)
            }

            if isPausedByUser, isReady, !isScrubbing {
                Image(systemName: "play.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.4), radius: 12)
                    .transition(.scale(scale: 1.3).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        // 輕點暫停 / 播放；按住超過 0.35 秒進入 2 倍速，鬆手恢復
        .onTapGesture {
            togglePause()
        }
        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 12) {
            setFastForward(true)
        } onPressingChanged: { pressing in
            if !pressing, isFastForwarding {
                setFastForward(false)
            }
        }
        .task(id: item.id) {
            await load()
        }
        .onChange(of: isActive) { _, active in
            if active { isPausedByUser = false }
            updatePlayback(active: active)
        }
        .onChange(of: mutedOverride) { _, muted in
            if let muted {
                isMuted = muted
                player.isMuted = muted
            }
        }
        .onDisappear {
            player.pause()
            teardown()
        }
    }

    private func load() async {
        isMuted = mutedOverride ?? model.settings.videoMuted
        player.isMuted = isMuted
        guard let asset = fetchAsset(item.id) else { return }
        let bag = RequestBag()
        bag.add(MediaLoader.shared.requestPlayerItem(for: asset, progress: { downloadProgress = $0 }) { playerItem in
            guard let playerItem else { return }
            player.replaceCurrentItem(with: playerItem)
            attachObservers(to: playerItem)
            isReady = true
            updatePlayback(active: isActive)
        })
        await MediaLoader.shared.hold(bag)
    }

    private func togglePause() {
        guard isActive, isReady else { return }
        Haptics.tick()
        let isPlaying = player.rate != 0
        withAnimation(.spring(duration: 0.25)) { isPausedByUser = isPlaying }
        if isPlaying { player.pause() } else { player.play() }
    }

    // MARK: - 拖動進度

    private func scrub(to fraction: Double) {
        if !isScrubbing {
            wasPlayingBeforeScrub = player.rate != 0
            player.pause()
            Haptics.tick()
            withAnimation(.easeOut(duration: 0.15)) { isScrubbing = true }
        }
        scrubFraction = fraction
        seek(to: fraction)
    }

    private func endScrub(at fraction: Double) {
        scrubFraction = fraction
        playbackProgress = fraction
        seek(to: fraction)
        withAnimation(.easeOut(duration: 0.2)) { isScrubbing = false }
        if wasPlayingBeforeScrub, isActive {
            isPausedByUser = false
            player.play()
        }
    }

    /// 拖動時連續跳轉：上一次跳轉完成前只記住最新目標，完成後再跳，避免堆積
    private func seek(to fraction: Double) {
        pendingSeek = fraction
        guard !isSeeking else { return }
        performPendingSeek()
    }

    private func performPendingSeek() {
        guard let fraction = pendingSeek else { return }
        pendingSeek = nil
        isSeeking = true
        let time = CMTime(seconds: fraction * duration, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
                isSeeking = false
                performPendingSeek()
            }
        }
    }

    // MARK: - 倍速

    private func setFastForward(_ on: Bool) {
        withAnimation(.easeOut(duration: 0.15)) { isFastForwarding = on }
        if on {
            Haptics.tick()
            isPausedByUser = false
            player.rate = 2.0
        } else {
            updatePlayback(active: isActive)
        }
    }

    private func updatePlayback(active: Bool) {
        if active && model.settings.videoAutoplay && !isPausedByUser {
            player.play()
        } else {
            player.pause()
        }
    }

    private func attachObservers(to playerItem: AVPlayerItem) {
        teardown()
        player.actionAtItemEnd = .none
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { time in
            // 拖動中以手指位置為準
            guard !isScrubbing else { return }
            playbackProgress = min(max(time.seconds / duration, 0), 1)
        }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            // 循環播放：actionAtItemEnd 設為 .none，播完回到開頭繼續（暫停中則停在開頭）
            player.seek(to: .zero)
        }
    }

    private func teardown() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        timeObserver = nil
        loopObserver = nil
    }
}

/// 可拖動的進度條：平時是一條細線；按住後變粗並出現圓點，跟著手指跳轉。
/// 觸控範圍比看到的線高很多，容易按到。
struct VideoScrubber: View {
    let loaded: Double
    let played: Double
    let isScrubbing: Bool
    var isEnabled = true
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void

    private let touchHeight: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let barHeight: CGFloat = isScrubbing ? 8 : 3
            let barY = proxy.size.height - barHeight / 2 - 1
            ZStack {
                Color.clear
                    .contentShape(Rectangle())

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white.opacity(0.35))
                        .frame(width: width * loaded)
                    Capsule().fill(.white)
                        .frame(width: width * played)
                }
                .frame(width: width, height: barHeight)
                .position(x: width / 2, y: barY)

                if isScrubbing {
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                        .position(x: min(max(width * played, 8), width - 8), y: barY)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        onChanged(fraction(value.location.x, width: width))
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        onEnded(fraction(value.location.x, width: width))
                    },
                including: isEnabled ? .all : .none
            )
        }
        .frame(height: touchHeight)
        .animation(.easeOut(duration: 0.15), value: isScrubbing)
    }

    private func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        min(max(Double(x / width), 0), 1)
    }
}

/// 用 AVPlayerLayer 顯示影片，可控制是否輸出 HDR。
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let hdr: Bool
    var fill = false

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
        view.playerLayer.wantsExtendedDynamicRangeContent = hdr
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.clipsToBounds = true
    }
}
