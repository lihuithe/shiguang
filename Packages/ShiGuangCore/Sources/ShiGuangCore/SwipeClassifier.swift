import Foundation

/// 首頁手勢：上滑刪除、下滑收藏、左滑下一張、右滑上一張。
public enum SwipeAction: Equatable, Sendable {
    case delete
    case favorite
    case next
    case previous
    case none
}

public enum SwipeClassifier {
    /// - Parameters:
    ///   - translation: 拖曳位移（y 向下為正，與 UIKit 座標一致）
    ///   - predictedEnd: 系統預測的結束位移，用來支援快速輕掃
    public static func classify(
        translationX dx: Double,
        translationY dy: Double,
        predictedEndX pdx: Double? = nil,
        predictedEndY pdy: Double? = nil,
        distanceThreshold: Double = 90,
        flickThreshold: Double = 220
    ) -> SwipeAction {
        let px = pdx ?? dx
        let py = pdy ?? dy
        let horizontal = abs(dx) + abs(px) * 0.5
        let vertical = abs(dy) + abs(py) * 0.5
        guard max(horizontal, vertical) > 0 else { return .none }

        if vertical >= horizontal {
            if dy <= -distanceThreshold || py <= -flickThreshold { return .delete }
            if dy >= distanceThreshold || py >= flickThreshold { return .favorite }
        } else {
            if dx <= -distanceThreshold || px <= -flickThreshold { return .next }
            if dx >= distanceThreshold || px >= flickThreshold { return .previous }
        }
        return .none
    }

    /// 雙指捏合縮小到此比例以下，進入「回到那天」。
    public static let pinchToDayThreshold: Double = 0.82

    public static func shouldOpenDay(pinchScale: Double) -> Bool {
        pinchScale > 0 && pinchScale <= pinchToDayThreshold
    }
}
