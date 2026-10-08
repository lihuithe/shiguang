import UIKit
import UserNotifications

/// 觸感回饋，可在設定中關閉。
@MainActor
enum Haptics {
    static var isEnabled = true

    static func delete() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func favorite() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.8)
    }

    static func tick() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// 每日回顧提醒。
enum ReminderService {
    private static let identifier = "daily-review-reminder"

    private static let messages = [
        "今天也来开一组盲盒吧，看看几年前的今天拍了什么。",
        "花一分钟回顾一组照片，顺手删掉废片。",
        "你的相册里还藏着很多被遗忘的瞬间。",
    ]

    /// 回傳是否成功取得通知權限並排程。
    static func schedule(hour: Int, minute: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "拾光"
        content.body = messages.randomElement() ?? messages[0]
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: hour, minute: minute),
            repeats: true
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
