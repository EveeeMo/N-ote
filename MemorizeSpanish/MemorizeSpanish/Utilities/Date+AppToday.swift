import Foundation

enum AppTime {
    private static let debugDayOffsetKey = "debug.dayOffset"

    /// Simulated day offset for testing queues (also available in Release via hidden debug entry).
    static var debugDayOffset: Int {
        get { UserDefaults.standard.integer(forKey: debugDayOffsetKey) }
        set { UserDefaults.standard.set(newValue, forKey: debugDayOffsetKey) }
    }

    static var today: Date {
        let base = Date()
        return Calendar.current.date(byAdding: .day, value: debugDayOffset, to: base) ?? base
    }

    /// 与「今日待复习」窗口对齐的当天0 点（含调试日偏移）。新建复习项应使用此时间，避免 `nextReview = .now` 落在逻辑日窗口外。
    static var startOfLogicalToday: Date {
        Calendar.current.startOfDay(for: today)
    }

    static func endOfToday() -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: today)
        return cal.date(byAdding: .day, value: 1, to: start)!
    }
}
