import Photos
import PhotosUI
import ShiGuangCore
import SwiftUI

/// 依媒體類型選擇顯示方式：照片（含 HDR）、實況照片、動圖、影片，或演示卡片。
struct MediaContentView: View {
    let item: MediaItem
    /// 只有目前這張才自動播放實況照片與影片
    var isActive = true

    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if DemoLibrary.isDemoID(item.id) {
                DemoCardView(item: item)
            } else if item.kind == .video {
                VideoContentView(item: item, isActive: isActive)
            } else if item.isLivePhoto {
                LivePhotoContentView(item: item, isActive: isActive)
            } else if item.isAnimated {
                AnimatedImageContentView(item: item)
            } else {
                PhotoContentView(item: item, hdr: model.effectiveHDR)
            }
        }
        .id(item.id)
    }
}

func fetchAsset(_ id: String) -> PHAsset? {
    PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
}

// MARK: - 照片

struct PhotoContentView: View {
    let item: MediaItem
    let hdr: Bool

    @State private var image: UIImage?
    @State private var isHDRImage = false
    @State private var downloadProgress: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .allowedDynamicRange(isHDRImage ? .high : .standard)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    ProgressView().tint(.white)
                }
                if let downloadProgress, downloadProgress < 1 {
                    ICloudProgressBadge(progress: downloadProgress)
                }
            }
            .task(id: "\(item.id)-\(hdr)") {
                await load(size: proxy.size)
            }
        }
    }

    private func load(size: CGSize) async {
        guard let asset = fetchAsset(item.id) else { return }
        let scale = UIScreen.main.scale
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let bag = RequestBag()
        let loader = MediaLoader.shared

        // 機會式載入：先出低解析度，再換高解析度；離線時至少能看到本機縮圖
        bag.add(loader.requestImage(for: asset, targetSize: target, progress: { downloadProgress = $0 }) { result, _ in
            if let result, !isHDRImage { image = result }
        })
        if hdr {
            bag.add(loader.requestHDRImage(for: asset, maxPixelSize: max(target.width, target.height)) { result in
                if let result {
                    image = result
                    isHDRImage = true
                }
            })
        } else {
            isHDRImage = false
        }
        await loader.hold(bag)
    }
}

struct ICloudProgressBadge: View {
    let progress: Double

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "icloud.and.arrow.down")
                ProgressView(value: progress)
                    .frame(width: 60)
                    .tint(.white)
            }
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 120)
        }
    }
}

// MARK: - 縮圖

struct ThumbnailView: View {
    let item: MediaItem
    var side: CGFloat = 120

    @State private var image: UIImage?

    /// 固定為正方形，圖片填滿裁切
    var body: some View {
        Color(white: 0.15)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if DemoLibrary.isDemoID(item.id) {
                    DemoCardView(item: item, compact: true)
                } else if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
        .task(id: item.id) {
            guard !DemoLibrary.isDemoID(item.id), let asset = fetchAsset(item.id) else { return }
            let scale = UIScreen.main.scale
            let bag = RequestBag()
            bag.add(MediaLoader.shared.requestImage(
                for: asset,
                targetSize: CGSize(width: side * scale, height: side * scale),
                contentMode: .aspectFill
            ) { result, _ in
                if let result { image = result }
            })
            await MediaLoader.shared.hold(bag)
        }
    }
}

// MARK: - 動圖

struct AnimatedImageContentView: View {
    let item: MediaItem
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                AnimatedImageView(image: image)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: item.id) {
            guard let asset = fetchAsset(item.id) else { return }
            let bag = RequestBag()
            bag.add(MediaLoader.shared.requestAnimatedImage(for: asset) { result in
                image = result
            })
            await MediaLoader.shared.hold(bag)
        }
    }
}

struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if view.image !== image {
            view.image = image
            view.startAnimating()
        }
    }
}

// MARK: - 實況照片

struct LivePhotoContentView: View {
    let item: MediaItem
    let isActive: Bool

    @Environment(AppModel.self) private var model
    @State private var livePhoto: PHLivePhoto?
    @State private var isFinal = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let livePhoto {
                    LivePhotoView(
                        livePhoto: livePhoto,
                        autoplay: isActive && isFinal && model.settings.livePhotoAutoplay,
                        muted: model.settings.livePhotoMuted
                    )
                } else {
                    PhotoContentView(item: item, hdr: false)
                }
                MediaBadge(title: "实况", systemImage: "livephoto")
                    .padding(.top, 110)
                    .padding(.leading, 16)
            }
            .task(id: item.id) {
                guard let asset = fetchAsset(item.id) else { return }
                let scale = UIScreen.main.scale
                let target = CGSize(width: proxy.size.width * scale, height: proxy.size.height * scale)
                let bag = RequestBag()
                bag.add(MediaLoader.shared.requestLivePhoto(for: asset, targetSize: target) { result, degraded in
                    if let result { livePhoto = result }
                    if !degraded { isFinal = true }
                })
                await MediaLoader.shared.hold(bag)
            }
        }
    }
}

struct MediaBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

struct LivePhotoView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let autoplay: Bool
    let muted: Bool

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        view.isMuted = muted
        let changed = view.livePhoto !== livePhoto
        if changed {
            view.livePhoto = livePhoto
            context.coordinator.didAutoplay = false
        }
        if autoplay, !context.coordinator.didAutoplay {
            context.coordinator.didAutoplay = true
            view.startPlayback(with: .full)
        } else if !autoplay {
            context.coordinator.didAutoplay = false
            view.stopPlayback()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var didAutoplay = false
    }
}
