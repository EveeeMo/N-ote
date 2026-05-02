import SwiftData
import SwiftUI

struct EditWordView: View {
    @Bindable var word: WordEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("单词") {
                Text(word.spanish).font(.headline)
            }
            Section("中文释义") {
                TextField("释义", text: $word.chinese)
            }
            Section("词性 / 原形") {
                TextField("词性", text: $word.partOfSpeech)
                if word.isVerb {
                    TextField("动词原形", text: Binding(
                        get: { word.lemma ?? "" },
                        set: { word.lemma = $0.isEmpty ? nil : $0 }
                    ))
                }
            }
            if word.isVerb {
                Section("动词变位") {
                    VerbConjugationSnippet(infinitive: word.infinitiveForConjugation)
                }
            }
            Section("备注") {
                TextField("词组、用法…", text: $word.userNote, axis: .vertical)
                    .lineLimit(3 ... 10)
            }
        }
        .navigationTitle("编辑")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    dismiss()
                }
            }
        }
    }
}

private struct VerbConjugationSnippet: View {
    let infinitive: String
    @AppStorage(ConjugationPreferences.storageKey) private var conjugationJSON: String = ""

    private static let service = ConjugationService()

    var body: some View {
        let tenses = ConjugationPreferences.enabledTenses(fromJSONString: conjugationJSON.isEmpty ? nil : conjugationJSON)
        Group {
            if tenses.isEmpty {
                Text("可在「设置 → 动词变位」中勾选要展示的时态。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tenses) { tense in
                        let forms = Self.service.conjugationTable(infinitive: infinitive, tense: tense)
                        Text("\(tense.rawValue)：\(forms.joined(separator: " · "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
