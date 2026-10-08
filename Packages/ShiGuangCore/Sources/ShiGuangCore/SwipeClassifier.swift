import Foundation

public enum DragAxis: Equatable, Sendable {
    case horizontal
    case vertical
}

public enum PageTurn: Equatable, Sendable {
    /// 下一張（向左或向上滑）
    case forward
    /// 上一張（向右或向下滑）
    case backward
    case none
}

/// 手勢判定。照片瀏覽：左右翻頁、上滑刪除；影片信息流：上下翻頁；雙指捏合：回到那天。
public enum SwipeClassifier {
    /// 移動超過這個距離後鎖定拖曳方向，之後只沿該方向回應
    public static func lockAxis(translationX dx: Double, translationY dy: Double, slop: Double = 10) -> DragAxis? {
        guard max(abs(dx), abs(dy)) >= slop else { return nil }
        return abs(dx) > abs(dy) ? .horizontal : .vertical
    }

    /// 沿翻頁方向的位移換算成翻頁結果。位移為負代表往「下一張」方向拖。
    /// - Parameters:
    ///   - translation: 實際位移
    ///   - predictedEnd: 系統預測的結束位移，用來支援快速輕掃
    ///   - pageLength: 頁面寬（或高）
    public static func pageTurn(translation: Double, predictedEnd: Double, pageLength: Double) -> PageTurn {
        guard pageLength > 0 else { return .none }
        if translation <= -pageLength * 0.25 || predictedEnd <= -pageLength * 0.5 { return .forward }
        if translation >= pageLength * 0.25 || predictedEnd >= pageLength * 0.5 { return .backward }
        return .none
    }

    /// 上滑刪除：往上拖超過高度的 18%，或往上快速輕掃。
    public static func shouldDelete(translationY: Double, predictedEndY: Double, height: Double) -> Bool {
        guard height > 0 else { return false }
        return translationY <= -height * 0.18 || predictedEndY <= -height * 0.45
    }

    /// 上滑過程的進度 0...1，用於卡片縮小與提示
    public static func deleteProgress(translationY: Double, height: Double) -> Double {
        guard height > 0, translationY < 0 else { return 0 }
        return min(-translationY / (height * 0.35), 1)
    }

    /// 雙指捏合縮小到此比例以下，進入「回到那天」。
    public static let pinchToDayThreshold: Double = 0.82

    public static func shouldOpenDay(pinchScale: Double) -> Bool {
        pinchScale > 0 && pinchScale <= pinchToDayThreshold
    }
}
