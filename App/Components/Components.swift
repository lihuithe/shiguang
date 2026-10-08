import ShiGuangCore
import SwiftUI

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .glassBackground(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// 縮圖角落的小標記：影片長度、實況、收藏。
struct ThumbnailBadges: View {
    let item: MediaItem
    var isFavorite = false

    var body: some View {
        HStack(spacing: 3) {
            if isFavorite {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
            if item.kind == .video {
                Text(DurationText.format(item.duration))
            } else if item.isLivePhoto {
                Image(systemName: "livephoto")
            } else if item.isAnimated {
                Text("GIF")
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.7), radius: 2)
        .padding(4)
    }
}

struct EmptyCategoryView: View {
    let title: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.5))
            Text("「\(title)」里还没有内容")
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

/// 三個分頁：照片 / 視頻 / 統計
enum AppTab: Hashable {
    case photos
    case videos
    case stats
}

extension View {
    /// iOS 26 使用原生液態玻璃，舊系統退回毛玻璃材質
    @ViewBuilder
    func glassBackground<S: Shape>(_ shape: S, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .environment(\.colorScheme, .dark)
        }
    }
}

/// 刪除時，動態島位置閃一下紅光，像照片被吸進去。
struct IslandGlow: View {
    let isOn: Bool

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.red)
                .frame(width: 140, height: 40)
                .blur(radius: 18)
                .opacity(isOn ? 0.9 : 0)
                .scaleEffect(isOn ? 1.15 : 0.6)
                .position(x: proxy.size.width / 2, y: max(proxy.safeAreaInsets.top * 0.45, 18))
                .animation(.easeOut(duration: isOn ? 0.18 : 0.5), value: isOn)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// 頂部的組內進度：細軌道上一段亮色指示目前位置。
struct GroupProgressTrack: View {
    let progress: Double
    var width: CGFloat = 110

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.22))
            Capsule()
                .fill(.white)
                .frame(width: max(width * progress, 10))
        }
        .frame(width: width, height: 3)
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}

/// 「點擊 ↶ 可以撤銷」提示
struct UndoHintPill: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("点击")
            Image(systemName: "arrow.uturn.backward")
            Text("可以撤销")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.blue, in: Capsule())
        .shadow(color: .blue.opacity(0.4), radius: 8)
    }
}

/// 時間 + 地點的資訊條，例如「7 年前 / 重庆市沙坪坝区」
struct DatePlaceText: View {
    let item: MediaItem
    var alignment: HorizontalAlignment = .center

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(DateDisplay.format(item.creationDate, style: model.settings.dateStyle, calendar: model.calendar))
                .font(.subheadline.weight(.semibold))
            if let place = model.locations.name(for: item) {
                Text(place)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .onAppear { model.locations.resolve(item) }
    }
}
