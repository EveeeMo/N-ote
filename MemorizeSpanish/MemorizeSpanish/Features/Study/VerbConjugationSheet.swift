import SwiftUI

struct VerbConjugationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let infinitive: String

    @AppStorage(ConjugationPreferences.storageKey) private var conjugationJSON: String = ""
    @State private var selectedTense: SpanishTense = .present
    private let service = ConjugationService()

    private var displayTenses: [SpanishTense] {
        ConjugationPreferences.enabledTenses(fromJSONString: conjugationJSON.isEmpty ? nil : conjugationJSON)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("原形：\(infinitive)")
                    .font(.headline)
                    .padding(.horizontal)

                if displayTenses.isEmpty {
                    Spacer()
                        .frame(minHeight: 24)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(displayTenses) { tense in
                                Button(tense.rawValue) {
                                    selectedTense = tense
                                }
                                .buttonStyle(.bordered)
                                .tint(selectedTense == tense ? Color.accentColor : .gray)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if !displayTenses.isEmpty {
                    let forms = service.conjugationTable(infinitive: infinitive, tense: selectedTense)
                    let labels = ConjugationService.personLabels
                    List(0 ..< 6, id: \.self) { i in
                        HStack {
                            Text(labels[i]).foregroundStyle(.secondary)
                            Spacer()
                            Text(forms.indices.contains(i) ? forms[i] : "—")
                                .font(.body.monospaced())
                        }
                    }
                    .listStyle(.plain)
                }

                Link(
                    "在 RAE 词典查看",
                    destination: URL(string: "https://dle.rae.es/\(infinitive.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? infinitive)")!
                )
                    .font(.footnote)
                    .padding(.horizontal)
            }
            .navigationTitle("变位")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                syncSelectedTense()
            }
            .onChange(of: conjugationJSON) { _, _ in
                syncSelectedTense()
            }
        }
    }

    private func syncSelectedTense() {
        let list = displayTenses
        guard !list.isEmpty else { return }
        if !list.contains(selectedTense) {
            selectedTense = list[0]
        }
    }
}
