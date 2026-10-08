import Foundation

/// 平台無關的媒體描述。App 層由 PHAsset 轉換而來，演示模式與測試則直接建構。
public struct MediaItem: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case photo
        case video
    }

    public let id: String
    public var kind: Kind
    public var creationDate: Date?
    public var isScreenshot: Bool
    public var isLivePhoto: Bool
    public var isAnimated: Bool
    public var isSelfie: Bool
    public var isFavorite: Bool
    public var duration: TimeInterval
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(
        id: String,
        kind: Kind = .photo,
        creationDate: Date? = nil,
        isScreenshot: Bool = false,
        isLivePhoto: Bool = false,
        isAnimated: Bool = false,
        isSelfie: Bool = false,
        isFavorite: Bool = false,
        duration: TimeInterval = 0,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.creationDate = creationDate
        self.isScreenshot = isScreenshot
        self.isLivePhoto = isLivePhoto
        self.isAnimated = isAnimated
        self.isSelfie = isSelfie
        self.isFavorite = isFavorite
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// 高度至少是寬度 2.5 倍的圖片視為長圖，需要專門的長圖瀏覽。
    public var isLongImage: Bool {
        kind == .photo && pixelWidth > 0 && Double(pixelHeight) >= Double(pixelWidth) * 2.5
    }
}
