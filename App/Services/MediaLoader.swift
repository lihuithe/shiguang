import AVFoundation
import ImageIO
import Photos
import UIKit

/// 圖片、實況照片、影片的載入。所有請求都允許從 iCloud 下載；
/// 開了「最佳化 iPhone 儲存空間」時，會先顯示本機的低解析度版本。
final class MediaLoader {
    static let shared = MediaLoader()

    let cachingManager = PHCachingImageManager()

    private init() {
        cachingManager.allowsCachingHighQualityImages = false
    }

    // MARK: - 預載

    private var cachedIDs: [String] = []
    private var cachedSize: CGSize = .zero

    func updatePrefetch(ids: [String], targetSize: CGSize) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var list: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in list.append(asset) }
        if !cachedIDs.isEmpty {
            let old = PHAsset.fetchAssets(withLocalIdentifiers: cachedIDs, options: nil)
            var oldList: [PHAsset] = []
            old.enumerateObjects { asset, _, _ in oldList.append(asset) }
            cachingManager.stopCachingImages(for: oldList, targetSize: cachedSize, contentMode: .aspectFit, options: nil)
        }
        cachingManager.startCachingImages(for: list, targetSize: targetSize, contentMode: .aspectFit, options: nil)
        cachedIDs = ids
        cachedSize = targetSize
    }

    // MARK: - 圖片

    /// 機會式載入：先回呼低解析度，再回呼高解析度。回傳請求 ID 以便取消。
    @discardableResult
    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (UIImage?, _ isDegraded: Bool) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.version = .current
        if let progress {
            options.progressHandler = { value, _, _, _ in
                DispatchQueue.main.async { progress(value) }
            }
        }
        return cachingManager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: options) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            completion(image, degraded)
        }
    }

    /// 只回呼一次的小縮圖（不從 iCloud 下載），用於取主色
    func thumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            cachingManager.requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func cancel(_ id: PHImageRequestID) {
        cachingManager.cancelImageRequest(id)
    }

    /// 讓 SwiftUI 的 `.task` 持有請求直到畫面消失，消失時取消所有請求。
    func hold(_ bag: RequestBag) async {
        await withTaskCancellationHandler {
            try? await Task.sleep(nanoseconds: .max)
        } onCancel: {
            for id in bag.ids { self.cancel(id) }
        }
    }

    /// HDR 照片：讀原始資料並以 UIImageReader 解碼保留高動態範圍。
    @discardableResult
    func requestHDRImage(for asset: PHAsset, maxPixelSize: CGFloat, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        options.deliveryMode = .highQualityFormat
        return cachingManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            guard let data else { return completion(nil) }
            DispatchQueue.global(qos: .userInitiated).async {
                var config = UIImageReader.Configuration()
                config.prefersHighDynamicRange = true
                config.preferredThumbnailSize = CGSize(width: maxPixelSize, height: maxPixelSize)
                let image = UIImageReader(configuration: config).image(data: data)
                DispatchQueue.main.async { completion(image) }
            }
        }
    }

    /// 動圖：讀取 GIF 資料，解成可播放的 UIImage。
    @discardableResult
    func requestAnimatedImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .original
        return cachingManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            guard let data else { return completion(nil) }
            DispatchQueue.global(qos: .userInitiated).async {
                let image = UIImage.animated(gifData: data) ?? UIImage(data: data)
                DispatchQueue.main.async { completion(image) }
            }
        }
    }

    // MARK: - 實況照片

    func requestLivePhoto(for asset: PHAsset, targetSize: CGSize, completion: @escaping (PHLivePhoto?, _ isDegraded: Bool) -> Void) -> PHImageRequestID {
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        return cachingManager.requestLivePhoto(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { live, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            completion(live, degraded)
        }
    }

    // MARK: - 影片

    func requestPlayerItem(for asset: PHAsset, progress: @escaping (Double) -> Void, completion: @escaping (AVPlayerItem?) -> Void) -> PHImageRequestID {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        options.version = .current
        options.progressHandler = { value, _, _, _ in
            DispatchQueue.main.async { progress(value) }
        }
        return cachingManager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
            DispatchQueue.main.async { completion(item) }
        }
    }
}

/// 收集一個畫面發出的 PhotoKit 請求 ID。
final class RequestBag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [PHImageRequestID] = []

    var ids: [PHImageRequestID] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func add(_ id: PHImageRequestID) {
        lock.lock(); defer { lock.unlock() }
        storage.append(id)
    }
}

extension MediaLoader: @unchecked Sendable {}

extension UIImage {
    /// 把 GIF 解碼成動畫 UIImage。單幀圖片回傳 nil。
    /// 每一幀縮小到 maxPixelSize 以內，避免大尺寸動圖佔用大量記憶體、拖慢翻頁。
    static func animated(gifData data: Data, maxPixelSize: Int = 900) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        var frames: [UIImage] = []
        var duration: Double = 0
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            duration += frameDuration(source: source, index: index)
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: duration > 0 ? duration : Double(frames.count) * 0.1)
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.1 }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let value = unclamped ?? clamped ?? 0.1
        return value < 0.02 ? 0.1 : value
    }
}
