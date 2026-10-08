import ShiGuangCore
import SwiftUI

/// 演示模式的假照片：依 ID 生成固定的漸層與圖示，錄屏時不會洩漏真實相簿。
struct DemoCardView: View {
    let item: MediaItem
    /// 縮圖：只顯示小圖示
    var compact = false
    /// 嵌在外部卡片裡：填滿外框，不自帶圓角與留白
    var embedded = false

    private static let palettes: [[Color]] = [
        [.orange, .pink],
        [.teal, .blue],
        [.indigo, .purple],
        [.mint, .green],
        [.yellow, .orange],
        [.cyan, .indigo],
        [.pink, .purple],
        [.brown, .orange],
    ]

    private static func seed(_ item: MediaItem) -> Int {
        item.id.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
    }

    private static func palette(for item: MediaItem) -> [Color] {
        palettes[abs(seed(item)) % palettes.count]
    }

    /// 背景主色
    static func baseColor(for item: MediaItem) -> Color {
        palette(for: item)[0].opacity(0.55)
    }

    private var symbol: String {
        if item.kind == .video { return "play.rectangle.fill" }
        if item.isScreenshot { return "iphone" }
        if item.isAnimated { return "sparkles" }
        if item.isSelfie { return "face.smiling" }
        let symbols = ["sun.max.fill", "leaf.fill", "cat.fill", "fork.knife", "mountain.2.fill", "airplane", "birthday.cake.fill", "camera.macro", "moon.stars.fill", "beach.umbrella.fill"]
        return symbols[abs(Self.seed(item) / 7) % symbols.count]
    }

    var body: some View {
        if compact || embedded {
            content
        } else {
            content
                .aspectRatio(item.isLongImage ? 0.4 : 0.75, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var content: some View {
        ZStack {
            LinearGradient(colors: Self.palette(for: item), startPoint: .topLeading, endPoint: .bottomTrailing)
            if compact {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                VStack(spacing: 16) {
                    Image(systemName: symbol)
                        .font(.system(size: 88))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 12)
                    Text("演示内容")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }
}
