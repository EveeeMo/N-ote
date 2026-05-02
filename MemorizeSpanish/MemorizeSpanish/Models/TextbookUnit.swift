import Foundation
import SwiftData

@Model
final class TextbookUnit {
    @Attribute(.unique) var stableId: String
    var title: String
    var bookId: String
    var sortOrder: Int
    @Relationship(deleteRule: .cascade, inverse: \WordEntry.unit)
    var words: [WordEntry] = []

    init(stableId: String, title: String, bookId: String, sortOrder: Int) {
        self.stableId = stableId
        self.title = title
        self.bookId = bookId
        self.sortOrder = sortOrder
    }
}
