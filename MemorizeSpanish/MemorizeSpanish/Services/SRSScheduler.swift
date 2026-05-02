import Foundation

/// SM-2 inspired scheduling. Quality: 0 = forgot, 1 = hard, 3 = good, 5 = easy (mapped from UI buttons)。
/// 复习排期**只按自然日**（与 `AppTime` 逻辑日对齐），`nextReview` 存目标日 0:00，不依赖具体钟点。
enum ReviewGrade: Int {
    case forgot = 0
    case vague = 1
    case remembered = 3
}

struct SRSScheduler {
    /// Minimum ease factor in SM-2
    private static let minEase = 1.3

    static func apply(grade: ReviewGrade, item: ReviewItem) {
        var ef = item.easeFactor
        var reps = item.repetitions
        var interval = item.intervalDays

        let q = grade.rawValue

        if grade == .forgot {
            reps = 0
            interval = 0
            ef = max(minEase, ef - 0.2)
        } else {
            ef = max(minEase, ef + (0.1 - (5 - Double(q)) * (0.08 + (5 - Double(q)) * 0.02)))
            if reps == 0 {
                interval = 1
            } else if reps == 1 {
                interval = 6
            } else {
                interval = round(interval * ef)
            }
            reps += 1
        }

        if interval < 1 { interval = 1 }

        item.easeFactor = ef
        item.repetitions = reps
        item.intervalDays = interval
        let days = max(1, Int(round(interval)))
        let cal = Calendar.current
        let baseDay = AppTime.startOfLogicalToday
        if let next = cal.date(byAdding: .day, value: days, to: baseDay) {
            item.nextReview = next
        } else {
            item.nextReview = baseDay.addingTimeInterval(Double(days) * 86_400)
        }
    }
}
