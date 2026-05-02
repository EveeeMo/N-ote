import Foundation
import SwiftData

/// 按西语字面（去空白、小写）合并重复词条，与导入/手动添加共用同一规则。
enum DedupeService {
    static func normalizeSpanish(_ raw: String) -> String {
        WordEntry.normalizeSpanish(raw)
    }

    /// 启动或导入后：补全 `dedupeKey` 并合并同键多条记录。
    static func backfillAndMerge(context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<WordEntry>())
        for w in all {
            if w.dedupeKey.isEmpty {
                w.dedupeKey = normalizeSpanish(w.spanish)
            }
            // 旧库无 lastActivityAt 或为异常值时，用 createdAt 兜底
            if w.lastActivityAt.timeIntervalSince1970 <= 0 || w.lastActivityAt < w.createdAt {
                w.lastActivityAt = w.createdAt
            }
        }
        mergeAllDuplicateKeys(context: context)
    }

    static func mergeAllDuplicateKeys(context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<WordEntry>()) else { return }
        var groups: [String: [WordEntry]] = [:]
        for w in all {
            let k = normalizeSpanish(w.spanish)
            guard !k.isEmpty else { continue }
            groups[k, default: []].append(w)
        }
        for (_, group) in groups where group.count > 1 {
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            let keeper = sorted[0]
            for dup in sorted.dropFirst() {
                mergeTextFields(keeper: keeper, duplicate: dup)
                absorbReviews(keeper: keeper, duplicate: dup, context: context)
                context.delete(dup)
            }
            keeper.dedupeKey = normalizeSpanish(keeper.spanish)
            let latest = sorted.map(\.lastActivityAt).max() ?? keeper.lastActivityAt
            keeper.lastActivityAt = latest
        }
    }

    static func applyBundledWord(_ w: BundledWordDTO, to entry: WordEntry, unit: TextbookUnit) {
        entry.spanish = w.es
        if !w.zh.isEmpty { entry.chinese = appendChineseDistinct(entry.chinese, w.zh) }
        entry.partOfSpeech = w.pos
        entry.lemma = w.lemma
        if let note = w.note, !note.isEmpty {
            if entry.userNote.isEmpty {
                entry.userNote = note
            } else if !entry.userNote.contains(note) {
                entry.userNote = entry.userNote + "\n" + note
            }
        }
        entry.unit = unit
        entry.dedupeKey = normalizeSpanish(w.es)
        entry.lastActivityAt = Date()
    }

    static func mergeManualIntoExisting(
        entry: WordEntry,
        spanish: String,
        chinese: String,
        partOfSpeech: String,
        lemma: String?,
        userNote: String,
        unit: TextbookUnit
    ) {
        entry.spanish = spanish
        if !chinese.isEmpty { entry.chinese = appendChineseDistinct(entry.chinese, chinese) }
        entry.partOfSpeech = partOfSpeech
        entry.lemma = lemma
        if !userNote.isEmpty {
            if entry.userNote.isEmpty {
                entry.userNote = userNote
            } else if !entry.userNote.contains(userNote) {
                entry.userNote = entry.userNote + "\n" + userNote
            }
        }
        entry.unit = unit
        entry.dedupeKey = normalizeSpanish(spanish)
        entry.lastActivityAt = Date()
    }

    /// 合并同一 `dedupeKey` 的多条（保留最早 `createdAt`），删除其余。
    static func collapseMatches(_ matches: [WordEntry], context: ModelContext) {
        guard matches.count > 1 else { return }
        let sorted = matches.sorted { $0.createdAt < $1.createdAt }
        let keeper = sorted[0]
        for dup in sorted.dropFirst() {
            mergeTextFields(keeper: keeper, duplicate: dup)
            absorbReviews(keeper: keeper, duplicate: dup, context: context)
            context.delete(dup)
        }
        keeper.dedupeKey = normalizeSpanish(keeper.spanish)
        let latest = sorted.map(\.lastActivityAt).max() ?? keeper.lastActivityAt
        keeper.lastActivityAt = latest
    }

    private static func mergeTextFields(keeper: WordEntry, duplicate: WordEntry) {
        if !duplicate.chinese.isEmpty {
            keeper.chinese = appendChineseDistinct(keeper.chinese, duplicate.chinese)
        }
        if keeper.userNote.isEmpty, !duplicate.userNote.isEmpty {
            keeper.userNote = duplicate.userNote
        } else if !duplicate.userNote.isEmpty, keeper.userNote != duplicate.userNote,
 !keeper.userNote.contains(duplicate.userNote)
        {
            keeper.userNote = keeper.userNote.isEmpty ? duplicate.userNote : keeper.userNote + "\n" + duplicate.userNote
        }
        if keeper.lemma == nil || keeper.lemma?.isEmpty == true, let l = duplicate.lemma, !l.isEmpty {
            keeper.lemma = l
        }
    }

    /// 合并中文释义：已有内容则用 `;` 追加新片段；与已有分段（按 `;` 切分）完全相同的不再重复追加。
    private static func appendChineseDistinct(_ existing: String, _ addition: String) -> String {
        let add = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !add.isEmpty else { return existing }
        let base = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { return add }
        if base == add { return base }
        let segments = base.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if segments.contains(add) { return existing }
        return base + ";" + add
    }

    private static func absorbReviews(keeper: WordEntry, duplicate: WordEntry, context: ModelContext) {
        let kr = keeper.review
        let dr = duplicate.review
        switch (kr, dr) {
        case (nil, nil):
            break
        case (let k?, nil):
            k.word = keeper
        case (nil, let d?):
            keeper.review = d
            d.word = keeper
        case (let k?, let d?):
            let win = pickBetterReview(k, d)
            let lose = win === k ? d : k
            keeper.review = win
            win.word = keeper
            lose.word = nil
            context.delete(lose)
        }
    }

    private static func pickBetterReview(_ a: ReviewItem, _ b: ReviewItem) -> ReviewItem {
        if a.repetitions != b.repetitions { return a.repetitions > b.repetitions ? a : b }
        if a.nextReview != b.nextReview { return a.nextReview < b.nextReview ? a : b }
        return a.easeFactor >= b.easeFactor ? a : b
    }
}
