import AVFoundation
import Photos
import ShiGuangCore
import SwiftUI

/// 影片：自動循環播放、長按倍速、底部顯示載入與播放進度。
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
    @State private var pressTask: Task<Void, Never>?

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
                                .background(.ultraThinMaterial, in: Circle())
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
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.opacity)
                }

                VideoProgressBar(
                    loaded: isReady ? 1 : downloadProgress,
                    played: playbackProgress
                )
                .padding(.horizontal, showsChrome ? 16 : 0)
                .padding(.bottom, progressInset)
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 12) {
        } onPressingChanged: { pressing in
            // onPressingChanged 在手指一按下就觸發，延遲一下才進入倍速，避免輕觸與滑動誤觸
            pressTask?.cancel()
            if pressing {
                pressTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    setFastForward(true)
                }
            } else if isFastForwarding {
                setFastForward(false)
            }
        }
        .task(id: item.id) {
            await load()
        }
        .onChange(of: isActive) { _, active in
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

    private func setFastForward(_ on: Bool) {
        withAnimation(.easeOut(duration: 0.15)) { isFastForwarding = on }
        if on {
            Haptics.tick()
            player.rate = 2.0
        } else {
            updatePlayback(active: isActive)
        }
    }

    private func updatePlayback(active: Bool) {
        if active && model.settings.videoAutoplay {
            player.play()
        } else {
            player.pause()
        }
    }

    private func attachObservers(to playerItem: AVPlayerItem) {
        teardown()
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
            player.seek(to: .zero)
            if isActive { player.play() }
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
