import Foundation
import SwiftData

enum StudyQueueService {
    /// Items due before the end of logical today (includes overdue).
    static func dueItems(context: ModelContext) throws -> [ReviewItem] {
        let end = AppTime.endOfToday()
        var descriptor = FetchDescriptor<ReviewItem>(
            predicate: #Predicate { $0.nextReview < end },
            sortBy: [SortDescriptor(\.nextReview, order: .forward)]
        )
        descriptor.fetchLimit = 500
        let rows = try context.fetch(descriptor)
        return rows.filter { $0.word != nil }
    }

    static func dueCount(context: ModelContext) throws -> Int {
        try dueItems(context: context).count
    }
}
