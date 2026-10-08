import Foundation

/// 演示模式用的假相簿：以固定種子生成，內容可重現，不會碰到使用者的真實照片。
public enum DemoLibrary {
    public static let idPrefix = "demo-"

    public static func isDemoID(_ id: String) -> Bool {
        id.hasPrefix(idPrefix)
    }

    public static func items(count: Int = 240, now: Date = Date(), seed: UInt64 = 20_251_008) -> [MediaItem] {
        var rng = SeededRandomNumberGenerator(seed: seed)
        let sixYears: TimeInterval = 6 * 365 * 86_400
        // 先產生一些「拍照日」，讓同一天有多張，方便演示「回到那天」
        let shootingDays: [TimeInterval] = (0..<max(count / 6, 1)).map { _ in
            Double.random(in: 0...sixYears, using: &rng)
        }
        return (0..<count).map { index in
            let dayOffset = shootingDays[Int.random(in: 0..<shootingDays.count, using: &rng)]
            let inDay = Double.random(in: 0...(10 * 3600), using: &rng)
            let date = now.addingTimeInterval(-dayOffset + inDay - 12 * 3600)
            let roll = Int.random(in: 0..<100, using: &rng)
            var item = MediaItem(id: "\(idPrefix)\(index)", creationDate: min(date, now), pixelWidth: 3024, pixelHeight: 4032)
            switch roll {
            case 0..<12:
                item.kind = .video
                item.duration = Double.random(in: 3...90, using: &rng)
                item.pixelWidth = 1920
                item.pixelHeight = 1080
            case 12..<24:
                item.isScreenshot = true
                item.pixelWidth = 1179
                item.pixelHeight = roll < 15 ? 6000 : 2556
            case 24..<29:
                item.isAnimated = true
                item.pixelWidth = 480
                item.pixelHeight = 480
            case 29..<45:
                item.isLivePhoto = true
            case 45..<55:
                item.isSelfie = true
                item.isLivePhoto = roll % 2 == 0
            default:
                break
            }
            return item
        }
    }
}
