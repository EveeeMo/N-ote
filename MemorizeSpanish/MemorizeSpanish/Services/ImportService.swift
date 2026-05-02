import Foundation
import SwiftData

enum ImportError: LocalizedError {
    case missingFile
    case decodeFailed
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .missingFile: return "找不到词表文件"
        case .decodeFailed: return "JSON 解析失败"
        case .invalidPayload: return "词表内容无效"
        }
    }
}

enum ImportService {
    /// 使用内存索引查找，避免在 `for` 循环内用 `#Predicate` 捕获变量时 SwiftData fetch 结果异常（表现为导入成功但 WordEntry 长期为 0）。
    @MainActor
    static func upsertUnits(_ dtos: [BundledUnitDTO], context: ModelContext) throws {
        var unitsByStable: [String: TextbookUnit] = [:]
        for u in try context.fetch(FetchDescriptor<TextbookUnit>()) {
            unitsByStable[u.stableId] = u
        }

        var wordCache = try context.fetch(FetchDescriptor<WordEntry>())
        var byStable: [String: WordEntry] = [:]
        for w in wordCache {
            byStable[w.stableId] = w
        }
        var byDedupe: [String: [WordEntry]] = [:]
        for w in wordCache where !w.dedupeKey.isEmpty {
            byDedupe[w.dedupeKey, default: []].append(w)
        }

        func reloadWordsFromStore() throws {
            wordCache = try context.fetch(FetchDescriptor<WordEntry>())
            byStable = [:]
            for w in wordCache {
                byStable[w.stableId] = w
            }
            byDedupe = [:]
            for w in wordCache where !w.dedupeKey.isEmpty {
                byDedupe[w.dedupeKey, default: []].append(w)
            }
        }

        func registerInserted(_ entry: WordEntry, dedupeKey key: String) {
            wordCache.append(entry)
            byStable[entry.stableId] = entry
            byDedupe[key, default: []].append(entry)
        }

        for dto in dtos {
            let unitStable = dto.unitId
            let unit: TextbookUnit
            if let u = unitsByStable[unitStable] {
                unit = u
                unit.title = dto.title
                unit.bookId = dto.bookId
                unit.sortOrder = dto.sortOrder
            } else {
                let u = TextbookUnit(stableId: unitStable, title: dto.title, bookId: dto.bookId, sortOrder: dto.sortOrder)
                context.insert(u)
                unitsByStable[unitStable] = u
                unit = u
            }

            for w in dto.words {
                let key = WordEntry.normalizeSpanish(w.es)
                guard !key.isEmpty else { continue }

                var byKey = byDedupe[key] ?? []
                if !byKey.isEmpty {
                    if byKey.count > 1 {
                        DedupeService.collapseMatches(byKey, context: context)
                        try reloadWordsFromStore()
                        byKey = byDedupe[key] ?? []
                    }
                    if let entry = byKey.first {
                        DedupeService.applyBundledWord(w, to: entry, unit: unit)
                        Self.ensureReview(entry: entry, context: context)
                        continue
                    }
                }

                let wordStable = Self.wordStableId(unitId: unitStable, spanish: w.es)
                if let entry = byStable[wordStable] {
                    DedupeService.applyBundledWord(w, to: entry, unit: unit)
                    Self.ensureReview(entry: entry, context: context)
                    try reloadWordsFromStore()
                    continue
                }

                let entry = WordEntry(
                    stableId: wordStable,
                    spanish: w.es,
                    chinese: w.zh,
                    partOfSpeech: w.pos,
                    lemma: w.lemma,
                    userNote: w.note ?? "",
                    unit: unit,
                    dedupeKey: key
                )
                context.insert(entry)
                let review = ReviewItem(nextReview: AppTime.startOfLogicalToday, intervalDays: 0, easeFactor: 2.5, repetitions: 0, word: entry)
                entry.review = review
                context.insert(review)
                registerInserted(entry, dedupeKey: key)
            }
        }
        DedupeService.mergeAllDuplicateKeys(context: context)
    }

    @MainActor
    static func importFromFile(url: URL, context: ModelContext) throws {
        let data = try Data(contentsOf: url)
        let units = try JSONDecoder().decode([BundledUnitDTO].self, from: data)
        guard !units.isEmpty else { throw ImportError.invalidPayload }
        try upsertUnits(units, context: context)
    }

    static func wordStableId(unitId: String, spanish: String) -> String {
        "\(unitId)|\(spanish.lowercased())"
    }

    static func ensureReview(entry: WordEntry, context: ModelContext) {
        if entry.review == nil {
            let review = ReviewItem(nextReview: AppTime.startOfLogicalToday, intervalDays: 0, easeFactor: 2.5, repetitions: 0, word: entry)
            entry.review = review
            context.insert(review)
        }
    }
}
