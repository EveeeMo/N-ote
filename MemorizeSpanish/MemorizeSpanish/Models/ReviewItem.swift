import Foundation
import SwiftData

@Model
final class ReviewItem {
    var nextReview: Date
    /// SM-2 interval in days
    var intervalDays: Double
    var easeFactor: Double
    var repetitions: Int
    var word: WordEntry?

    init(
        nextReview: Date = .now,
        intervalDays: Double = 0,
        easeFactor: Double = 2.5,
        repetitions: Int = 0,
        word: WordEntry? = nil
    ) {
        self.nextReview = nextReview
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.repetitions = repetitions
        self.word = word
    }
}
