import SwiftUI
import UIKit

/// 只在「明確往上拖」時才開始的平移手勢（UIKit 手勢辨識器）。
///
/// 掛在原生分頁 ScrollView 的頁面上時，左右滑動完全交給 ScrollView，
/// 不會像 SwiftUI 的 DragGesture 那樣和滾動搶觸控，翻頁不會有延遲感。
struct UpwardPanGesture: UIGestureRecognizerRepresentable {
    var isEnabled = true
    /// 往上拖的位移（負值）
    var onChanged: (CGFloat) -> Void
    /// 結束時的位移與預測的最終位移
    var onEnded: (_ translationY: CGFloat, _ predictedEndY: CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).y
        switch recognizer.state {
        case .began, .changed:
            onChanged(translation)
        case .ended:
            // 依目前速度推算約 0.2 秒後的位置，支援快速輕掃
            let velocity = recognizer.velocity(in: recognizer.view).y
            onEnded(translation, translation + velocity * 0.2)
        case .cancelled, .failed:
            onEnded(0, 0)
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            let translation = pan.translation(in: pan.view)
            let dy = abs(velocity.y) > 1 ? velocity.y : translation.y
            let dx = abs(velocity.x) > 1 ? velocity.x : translation.x
            return dy < 0 && abs(dy) > abs(dx) * 1.3
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}
