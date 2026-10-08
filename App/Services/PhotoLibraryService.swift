import Photos
import ShiGuangCore
import UIKit

extension MediaItem {
    init(asset: PHAsset, isSelfie: Bool = false) {
        self.init(
            id: asset.localIdentifier,
            kind: asset.mediaType == .video ? .video : .photo,
            creationDate: asset.creationDate,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            isAnimated: asset.playbackStyle == .imageAnimated,
            isSelfie: isSelfie,
            isFavorite: asset.isFavorite,
            duration: asset.duration,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight
        )
    }
}

/// 把 PHFetchResult 包成可隨機存取的來源，只在抽到時才建立 MediaItem。
struct PHAssetSource: MediaSource {
    let fetchResult: PHFetchResult<PHAsset>
    let isSelfieCategory: Bool

    var count: Int { fetchResult.count }

    func item(at index: Int) -> MediaItem {
        MediaItem(asset: fetchResult.object(at: index), isSelfie: isSelfieCategory)
    }
}

enum PhotoLibraryError: LocalizedError {
    case userCancelled
    case failed(Error)

    var errorDescription: String? {
        switch self {
        case .userCancelled: return "已取消"
        case let .failed(error): return error.localizedDescription
        }
    }
}

/// PhotoKit 的薄封裝：授權、按類別取資料、按天取資料、刪除與收藏。
final class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver {
    /// 相簿內容變化時在主執行緒回呼
    var onChange: (() -> Void)?
    private var isRegistered = false

    var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    var hasAccess: Bool {
        status == .authorized || status == .limited
    }

    deinit {
        if isRegistered {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    @discardableResult
    func requestAccess() async -> PHAuthorizationStatus {
        let result = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        registerIfNeeded()
        return result
    }

    func registerIfNeeded() {
        guard hasAccess, !isRegistered else { return }
        PHPhotoLibrary.shared().register(self)
        isRegistered = true
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }

    // MARK: - 查詢

    func source(for category: MediaCategory) -> PHAssetSource {
        PHAssetSource(fetchResult: fetchResult(for: category), isSelfieCategory: category == .selfies)
    }

    func fetchResult(for category: MediaCategory) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
        let image = PHAssetMediaType.image.rawValue
        let video = PHAssetMediaType.video.rawValue
        let screenshot = PHAssetMediaSubtype.photoScreenshot.rawValue
        let live = PHAssetMediaSubtype.photoLive.rawValue

        switch category {
        case .all:
            options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", image, video)
            return PHAsset.fetchAssets(with: options)
        case .photos:
            options.predicate = NSPredicate(format: "mediaType == %d AND (mediaSubtypes & %d) == 0", image, screenshot)
            return PHAsset.fetchAssets(with: options)
        case .videos:
            options.predicate = NSPredicate(format: "mediaType == %d", video)
            return PHAsset.fetchAssets(with: options)
        case .screenshots:
            options.predicate = NSPredicate(format: "mediaType == %d AND (mediaSubtypes & %d) != 0", image, screenshot)
            return PHAsset.fetchAssets(with: options)
        case .livePhotos:
            options.predicate = NSPredicate(format: "mediaType == %d AND (mediaSubtypes & %d) != 0", image, live)
            return PHAsset.fetchAssets(with: options)
        case .animated:
            return smartAlbumAssets(.smartAlbumAnimated)
        case .selfies:
            return smartAlbumAssets(.smartAlbumSelfPortraits)
        }
    }

    private func smartAlbumAssets(_ subtype: PHAssetCollectionSubtype) -> PHFetchResult<PHAsset> {
        let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
        guard let collection = collections.firstObject else {
            return PHAsset.fetchAssets(withLocalIdentifiers: [], options: nil)
        }
        return PHAsset.fetchAssets(in: collection, options: nil)
    }

    /// 「回到那天」：某天拍攝的全部照片與影片，按時間排序。
    func assets(onDayOf date: Date, calendar: Calendar) -> [PHAsset] {
        let range = DayBucket.range(containing: date, calendar: calendar)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@ AND (mediaType == %d OR mediaType == %d)",
            range.start as NSDate, range.end as NSDate,
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func asset(withID id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    func allAssetIDs(in category: MediaCategory) -> [String] {
        let result = fetchResult(for: category)
        var ids: [String] = []
        ids.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return ids
    }

    // MARK: - 修改

    /// 刪除照片。系統會彈出確認框，刪除的項目進入「最近刪除」，30 天內可在照片 App 復原。
    func delete(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == PHPhotosErrorDomain, nsError.code == PHPhotosError.Code.userCancelled.rawValue {
                throw PhotoLibraryError.userCancelled
            }
            throw PhotoLibraryError.failed(error)
        }
    }

    /// 收藏會同步到系統照片的「個人收藏」。
    func setFavorite(_ favorite: Bool, id: String) async throws {
        guard let asset = asset(withID: id) else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).isFavorite = favorite
        }
    }

    /// 估算檔案大小（含實況照片的影片部分），用於統計釋放的空間。
    func estimatedFileSizes(ids: [String]) -> [String: Int64] {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var sizes: [String: Int64] = [:]
        assets.enumerateObjects { asset, _, _ in
            sizes[asset.localIdentifier] = Self.fileSize(of: asset)
        }
        return sizes
    }

    static func fileSize(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(Int64(0)) { total, resource in
            total + ((resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0)
        }
    }

    static func originalFilename(of asset: PHAsset) -> String? {
        PHAssetResource.assetResources(for: asset).first?.originalFilename
    }

    @MainActor
    func presentLimitedLibraryPicker() {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}
