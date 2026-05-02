import Foundation
import SwiftData

@Model
final class WordEntry {
    @Attribute(.unique) var stableId: String
    /// 西语去空白、小写，用于全局去重合并（与 `ImportService` / `DedupeService` 一致）。
    var dedupeKey: String
    var spanish: String
    var chinese: String
    var partOfSpeech: String
    var lemma: String?
    var userNote: String
    var createdAt: Date
    /// 最近导入、合并或手动保存的时间；词库汇总按此排序，避免合并进旧词条后「消失」在很早的日期里。
    var lastActivityAt: Date
    var unit: TextbookUnit?
    @Relationship(deleteRule: .cascade, inverse: \ReviewItem.word)
    var review: ReviewItem?

    init(
        stableId: String,
        spanish: String,
        chinese: String,
        partOfSpeech: String,
        lemma: String? = nil,
        userNote: String = "",
        createdAt: Date = .now,
        lastActivityAt: Date? = nil,
        unit: TextbookUnit? = nil,
        dedupeKey: String? = nil
    ) {
        self.stableId = stableId
        self.dedupeKey = dedupeKey ?? Self.normalizeSpanish(spanish)
        self.spanish = spanish
        self.chinese = chinese
        self.partOfSpeech = partOfSpeech
        self.lemma = lemma
        self.userNote = userNote
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt ?? createdAt
        self.unit = unit
    }

    var isVerb: Bool {
        partOfSpeech.lowercased() == "verb" || partOfSpeech.lowercased() == "v"
    }

    /// Infinitive used for conjugation: explicit lemma or the stored Spanish form.
    var infinitiveForConjugation: String {
        let raw = (lemma?.isEmpty == false ? lemma! : spanish).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.lowercased()
    }

    static func normalizeSpanish(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
