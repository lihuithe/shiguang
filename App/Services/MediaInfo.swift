import AVFoundation
import CoreImage
import CoreLocation
import Observation
import Photos
import ShiGuangCore
import SwiftUI

/// 把照片的拍攝地點反查成「四川省成都市都江堰市」這樣的中文地名，結果按媒體快取。
@MainActor
@Observable
final class LocationNamer {
    private(set) var names: [String: String] = [:]
    @ObservationIgnored private var pending = Set<String>()

    private static let demoPlaces = [
        "重庆市沙坪坝区", "四川省成都市都江堰市", "上海市静安区", "浙江省杭州市上城区",
        "北京市朝阳区", "广东省深圳市南山区", "云南省大理白族自治州大理市",
    ]

    func name(for item: MediaItem) -> String? {
        names[item.id]
    }

    func resolve(_ item: MediaItem) {
        let id = item.id
        guard names[id] == nil, !pending.contains(id) else { return }
        if DemoLibrary.isDemoID(id) {
            let hash = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
            names[id] = Self.demoPlaces[abs(hash) % Self.demoPlaces.count]
            return
        }
        guard let location = fetchAsset(id)?.location else { return }
        pending.insert(id)
        Task {
            defer { pending.remove(id) }
            let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN"))
            if let placemark = placemarks?.first, let text = Self.format(placemark) {
                names[id] = text
            }
        }
    }

    /// 省、市、區依序拼接，去掉直轄市重複的「重庆市重庆市」
    static func format(_ placemark: CLPlacemark) -> String? {
        var parts: [String] = []
        for part in [placemark.administrativeArea, placemark.locality, placemark.subLocality].compactMap({ $0 }) {
            if !part.isEmpty, parts.last != part { parts.append(part) }
        }
        if parts.isEmpty, let name = placemark.name { parts.append(name) }
        return parts.isEmpty ? nil : parts.joined()
    }
}

/// 取照片主色，作為瀏覽頁與首頁的背景色。
@MainActor
enum ColorExtractor {
    private static var cache: [String: Color] = [:]
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func color(for item: MediaItem) async -> Color {
        if let cached = cache[item.id] { return cached }
        let color: Color
        if DemoLibrary.isDemoID(item.id) {
            color = DemoCardView.baseColor(for: item)
        } else if let asset = fetchAsset(item.id),
                  let image = await MediaLoader.shared.thumbnail(for: asset, side: 48),
                  let average = averageColor(of: image) {
            color = Color(uiColor: average)
        } else {
            color = Color(white: 0.15)
        }
        cache[item.id] = color
        return color
    }

    private static func averageColor(of image: UIImage) -> UIColor? {
        guard let input = CIImage(image: image) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        // 調暗、保留色相，讓白色文字與按鈕清楚
        let color = UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: min(s * 1.1, 0.75), brightness: min(max(b * 0.6, 0.18), 0.45), alpha: 1)
    }
}

/// 分享：照片分享原始檔案，影片分享檔案 URL，演示內容分享渲染出的圖片。
struct ShareRequest: Identifiable {
    let id = UUID()
    let items: [Any]
}

@MainActor
enum ShareService {
    static func request(for item: MediaItem) async -> ShareRequest? {
        if DemoLibrary.isDemoID(item.id) {
            let renderer = ImageRenderer(content: DemoCardView(item: item, embedded: true).frame(width: 600, height: 800))
            renderer.scale = 2
            return renderer.uiImage.map { ShareRequest(items: [$0]) }
        }
        guard let asset = fetchAsset(item.id) else { return nil }
        if asset.mediaType == .video {
            guard let url = await videoURL(for: asset) else { return nil }
            return ShareRequest(items: [url])
        }
        guard let url = await imageFileURL(for: asset) else { return nil }
        return ShareRequest(items: [url])
    }

    private static func videoURL(for asset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
        }
    }

    private static func imageFileURL(for asset: PHAsset) async -> URL? {
        let data: Data? = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = PhotoLibraryService.originalFilename(of: asset) ?? "photo.jpg"
        let url = folder.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
