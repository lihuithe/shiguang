import AVFoundation
import Photos
import ShiGuangCore
import SwiftUI

/// 影片：自動循環播放、輕點暫停 / 播放、長按 2 倍速、底部顯示載入與播放進度。
struct VideoContentView: View {
    let item: MediaItem
    let isActive: Bool
    /// 顯示時長標記與靜音按鈕；嵌在信息流時由外層提供控制元件
    var showsChrome = true
    /// 由外部控制是否靜音；nil 表示用設定值，並允許使用者用按鈕切換
    var mutedOverride: Bool? = nil
    /// 進度條距離底部的距離
    var progressInset: CGFloat = 104

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

    var body: some View {
        ZStack {
            PhotoContentView(item: item, hdr: false)
                .opacity(isReady ? 0 : 1)

            PlayerLayerView(player: player, hdr: model.effectiveHDR)
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

                if isFastForwarding {
                    Label("2× 倍速播放中", systemImage: "forward.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassBackground(Capsule(), interactive: false)
                        .transition(.opacity)
                }

                VideoProgressBar(
                    loaded: isReady ? 1 : downloadProgress,
                    played: playbackProgress
                )
                .padding(.horizontal, showsChrome ? 16 : 0)
                .padding(.bottom, progressInset)
            }

            if isPausedByUser, isReady {
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
        let duration = max(item.duration, 0.1)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { time in
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

struct VideoProgressBar: View {
    let loaded: Double
    let played: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white.opacity(0.35))
                    .frame(width: proxy.size.width * loaded)
                Capsule().fill(.white)
                    .frame(width: proxy.size.width * played)
            }
        }
        .frame(height: 3)
        .animation(.linear(duration: 0.1), value: played)
    }
}

/// 用 AVPlayerLayer 顯示影片，可控制是否輸出 HDR。
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let hdr: Bool

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
    }
}
