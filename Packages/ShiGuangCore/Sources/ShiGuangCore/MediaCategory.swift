import Foundation

/// 首頁可切換的回顧類別。
public enum MediaCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 照片與影片混合瀏覽
    case all
    case photos
    case videos
    case screenshots
    case animated
    case livePhotos
    case selfies

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "全部"
        case .photos: return "照片"
        case .videos: return "视频"
        case .screenshots: return "截图"
        case .animated: return "动图"
        case .livePhotos: return "实况"
        case .selfies: return "自拍"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: return "square.stack"
        case .photos: return "photo"
        case .videos: return "video"
        case .screenshots: return "camera.viewfinder"
        case .animated: return "square.stack.3d.forward.dottedline"
        case .livePhotos: return "livephoto"
        case .selfies: return "person.crop.square"
        }
    }

    /// 判斷某個媒體是否屬於此類別。App 層用 PhotoKit 的查詢與智慧相簿取資料，
    /// 這裡的規則用於演示模式、測試，以及「回到那天」的類別篩選。
    public func contains(_ item: MediaItem) -> Bool {
        switch self {
        case .all: return true
        case .photos: return item.kind == .photo && !item.isScreenshot && !item.isAnimated
        case .videos: return item.kind == .video
        case .screenshots: return item.isScreenshot
        case .animated: return item.isAnimated
        case .livePhotos: return item.isLivePhoto
        case .selfies: return item.isSelfie
        }
    }
}
