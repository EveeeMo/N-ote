import Foundation

/// JSON shape for bundled and imported units.
struct BundledUnitDTO: Codable, Sendable, Hashable, Identifiable {
    var id: String { unitId }
    var unitId: String
    var title: String
    var bookId: String
    var sortOrder: Int
    var words: [BundledWordDTO]
}

struct BundledWordDTO: Codable, Sendable, Hashable {
    var es: String
    var zh: String
    var pos: String
    var lemma: String?
    var note: String?
}
