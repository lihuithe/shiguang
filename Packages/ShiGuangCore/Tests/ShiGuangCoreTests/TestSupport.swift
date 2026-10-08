import Foundation
@testable import ShiGuangCore

enum TestSupport {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func items(_ count: Int, prefix: String = "a") -> [MediaItem] {
        (0..<count).map { MediaItem(id: "\(prefix)\($0)", creationDate: date(2024, 1, 1)) }
    }
}
