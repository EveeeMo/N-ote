import SwiftData
import SwiftUI

struct AddWordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var unit: TextbookUnit

    @State private var spanish = ""
    @State private var chinese = ""
    @State private var partOfSpeech = "noun"
    @State private var lemma = ""
    @State private var userNote = ""
    @State private var isTranslating = false
    @State private var translateError: String?
    @State private var saveError: String?

    private let translator: TranslationService = MyMemoryTranslationService()
    private let posOptions = ["noun", "verb", "adj", "adv", "prep", "interj", "phrase"]

    var body: some View {
        Form {
            Section("西语") {
                TextField("单词或短语", text: $spanish)
                Button {
                    Task { await runTranslate() }
                } label: {
                    if isTranslating {
                        ProgressView("翻译中…")
                    } else {
                        Label("自动填充中文与词性（联网）", systemImage: "globe")
                    }
                }
                .disabled(spanish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
            }

            Section("中文") {
                TextField("释义", text: $chinese)
            }

            Section("属性") {
                Picker("词性", selection: $partOfSpeech) {
                    ForEach(posOptions, id: \.self) { Text($0).tag($0) }
                }
                if partOfSpeech == "verb" {
                    TextField("原形（可与上面相同）", text: $lemma)
                }
            }

            Section("备注") {
                TextField("词组、用法…", text: $userNote, axis: .vertical)
                    .lineLimit(3 ... 8)
            }

            if let translateError {
                Section {
                    Text(translateError).foregroundStyle(.red)
                }
            }
            if let saveError {
                Section {
                    Text(saveError).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("添加单词")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(spanish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func runTranslate() async {
        isTranslating = true
        translateError = nil
        defer { isTranslating = false }
        do {
            let zh = try await translator.translateSpanishToChinese(spanish)
            if zh.isEmpty {
                translateError = "未获取到译文，请手动填写。"
            } else {
                chinese = zh
                partOfSpeech = SpanishPOSInference.appPartOfSpeech(for: spanish)
            }
        } catch {
            translateError = "翻译失败：\(error.localizedDescription)"
        }
    }

    private func save() {
        saveError = nil
        let es = spanish.trimmingCharacters(in: .whitespacesAndNewlines)
        let zh = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = WordEntry.normalizeSpanish(es)
        guard !key.isEmpty else { return }

        let lem = partOfSpeech == "verb"
            ? (lemma.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? es : lemma.trimmingCharacters(in: .whitespacesAndNewlines))
            : nil

        let dedupeFetch = FetchDescriptor<WordEntry>(predicate: #Predicate { $0.dedupeKey == key })
        if let rows = try? modelContext.fetch(dedupeFetch), !rows.isEmpty {
            if rows.count > 1 {
                DedupeService.collapseMatches(rows, context: modelContext)
            }
            guard let entry = try? modelContext.fetch(dedupeFetch).first else { return }
            DedupeService.mergeManualIntoExisting(
                entry: entry,
                spanish: es,
                chinese: zh,
                partOfSpeech: partOfSpeech,
                lemma: lem,
                userNote: note,
                unit: unit
            )
            ImportService.ensureReview(entry: entry, context: modelContext)
            persistAndDismiss()
            return
        }

        let stable = ImportService.wordStableId(unitId: unit.stableId, spanish: es)
        let stableFetch = FetchDescriptor<WordEntry>(predicate: #Predicate { $0.stableId == stable })
        if let hit = try? modelContext.fetch(stableFetch).first {
            DedupeService.mergeManualIntoExisting(
                entry: hit,
                spanish: es,
                chinese: zh,
                partOfSpeech: partOfSpeech,
                lemma: lem,
                userNote: note,
                unit: unit
            )
            ImportService.ensureReview(entry: hit, context: modelContext)
            persistAndDismiss()
            return
        }

        let entry = WordEntry(
            stableId: stable,
            spanish: es,
            chinese: zh,
            partOfSpeech: partOfSpeech,
            lemma: lem,
            userNote: note,
            unit: unit,
            dedupeKey: key
        )
        modelContext.insert(entry)
        let review = ReviewItem(nextReview: AppTime.startOfLogicalToday, intervalDays: 0, easeFactor: 2.5, repetitions: 0, word: entry)
        entry.review = review
        modelContext.insert(review)
        persistAndDismiss()
    }

    private func persistAndDismiss() {
        do {
            try DataRefresh.afterImportMutation(context: modelContext)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
