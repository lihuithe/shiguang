import Foundation

/// 「回到那天」時間軸：多排橫向瀑布流。每一項依時間順序放進目前最短的那一排，
/// 寬度依照片比例決定，因此各排長度接近、上下不必對齊（與原版一致）。
public struct TimelineLayout: Equatable {
    public struct Frame: Equatable {
        public var row: Int
        public var x: Double
        public var width: Double

        public init(row: Int, x: Double, width: Double) {
            self.row = row
            self.x = x
            self.width = width
        }

        public var midX: Double { x + width / 2 }
    }

    public let rows: Int
    public let rowHeight: Double
    public let spacing: Double
    /// 與輸入項目一一對應
    public let frames: [Frame]
    /// 最長那一排的長度
    public let contentWidth: Double

    /// 太寬或太窄的照片會被裁切到這個比例範圍
    public static let aspectRange: ClosedRange<Double> = 0.55...1.8

    public init(items: [MediaItem], rows: Int, rowHeight: Double, spacing: Double) {
        let rows = max(rows, 1)
        self.rows = rows
        self.rowHeight = rowHeight
        self.spacing = spacing
        var rowEnds = [Double](repeating: 0, count: rows)
        var frames: [Frame] = []
        frames.reserveCapacity(items.count)
        for item in items {
            let aspect = TimelineLayout.aspect(of: item)
            let width = (rowHeight * aspect).rounded()
            // 放進目前最短的一排；長度相同時放上面那排
            var row = 0
            for index in 1..<rows where rowEnds[index] < rowEnds[row] {
                row = index
            }
            frames.append(Frame(row: row, x: rowEnds[row], width: width))
            rowEnds[row] += width + spacing
        }
        self.frames = frames
        self.contentWidth = max((rowEnds.max() ?? 0) - spacing, 0)
    }

    public static func aspect(of item: MediaItem) -> Double {
        guard item.pixelWidth > 0, item.pixelHeight > 0 else { return 0.75 }
        let raw = Double(item.pixelWidth) / Double(item.pixelHeight)
        return min(max(raw, aspectRange.lowerBound), aspectRange.upperBound)
    }

    /// 距離某個 x 座標最近的項目索引（用於標題日期、刻度尺與「回到起點」）
    public func index(nearestX x: Double) -> Int? {
        guard !frames.isEmpty else { return nil }
        var best = 0
        var bestDistance = Double.infinity
        for (index, frame) in frames.enumerated() {
            let distance = abs(frame.midX - x)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    /// 讓某一項置中時的捲動偏移量
    public func offset(centering index: Int, viewportWidth: Double) -> Double {
        guard frames.indices.contains(index) else { return 0 }
        let maxOffset = max(contentWidth - viewportWidth, 0)
        return min(max(frames[index].midX - viewportWidth / 2, 0), maxOffset)
    }
}

/// 在依時間排序的序列中找出最接近某個時間的位置。用閉包取日期，App 層可直接查 PHFetchResult。
public enum TimelineSearch {
    /// 第一個時間 >= target 的索引；全部都更早則回傳 count。沒有日期的項目視為最早。
    public static func lowerBound(count: Int, target: Date, date: (Int) -> Date?) -> Int {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if (date(mid) ?? .distantPast) < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    /// 以 center 為中心、最多 radius 項的視窗範圍
    public static func window(around center: Int, radius: Int, count: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let clamped = min(max(center, 0), count - 1)
        let lower = max(clamped - radius, 0)
        let upper = min(clamped + radius + 1, count)
        return lower..<upper
    }
}
