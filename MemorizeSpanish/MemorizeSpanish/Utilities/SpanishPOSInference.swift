import Foundation
import NaturalLanguage

/// 用系统 `NLTagger` 对西语做词性标注，映射到应用内 `WordEntry.partOfSpeech` 取值。
enum SpanishPOSInference {
    /// 与 `AddWordView.posOptions` 一致：`noun` / `verb` / `adj` / `adv` / `prep` / `interj` / `phrase`
    static func appPartOfSpeech(for spanish: String) -> String {
        let trimmed = spanish.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "noun" }

        let words = trimmed.split { $0.isWhitespace }.map(String.init)
        guard !words.isEmpty else { return "noun" }

        if words.count > 1 {
            let tags = words.map { inferredPOSForSingleToken($0) }
            if let first = tags.first, tags.allSatisfy({ $0 == first }) {
                return first
            }
            return "phrase"
        }

        return inferredPOSForSingleToken(words[0])
    }

    private static func inferredPOSForSingleToken(_ word: String) -> String {
        let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
        guard !cleaned.isEmpty else { return "noun" }

        let lowered = cleaned.lowercased()
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = lowered
        let fullRange = lowered.startIndex..<lowered.endIndex
        tagger.setLanguage(.spanish, range: fullRange)

        var found: NLTag?
        tagger.enumerateTags(in: fullRange, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            found = tag
            return false
        }

        if let tag = found, tag != .otherWord, let mapped = mapLexicalTag(tag) {
            return mapped
        }

        return heuristicFallback(lowered)
    }

    private static func mapLexicalTag(_ tag: NLTag) -> String? {
        switch tag {
        case .noun, .pronoun:
            return "noun"
        case .verb:
            return "verb"
        case .adjective:
            return "adj"
        case .adverb:
            return "adv"
        case .preposition:
            return "prep"
        case .interjection:
            return "interj"
        case .conjunction, .determiner, .particle, .otherWord:
            return nil
        default:
            return nil
        }
    }

    private static func heuristicFallback(_ lowered: String) -> String {
        if ["ir", "ser", "dar", "ver", "estar"].contains(lowered) {
            return "verb"
        }
        if lowered.count >= 3 {
            if lowered.hasSuffix("ar") || lowered.hasSuffix("er") || lowered.hasSuffix("ir") {
                return "verb"
            }
        }
        if lowered.hasSuffix("mente") {
            return "adv"
        }
        if lowered.hasSuffix("ción") || lowered.hasSuffix("sión") || lowered.hasSuffix("dad") {
            return "noun"
        }
        return "noun"
    }
}
