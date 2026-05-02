import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WordEntry.createdAt, order: .reverse) private var words: [WordEntry]

    @State private var searchText = ""

    private var filteredWords: [WordEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return words }
        return words.filter { w in
            w.spanish.localizedCaseInsensitiveContains(q)
                || w.chinese.localizedCaseInsensitiveContains(q)
                || w.dedupeKey.contains(q.lowercased())
        }
    }

    private var dateSections: [(day: Date, items: [WordEntry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filteredWords, by: { cal.startOfDay(for: $0.createdAt) })
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day]!.sorted { $0.createdAt > $1.createdAt })
        }
    }

    private func sectionTitle(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "今天" }
        if cal.isDateInYesterday(day) { return "昨天" }
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        f.locale = Locale(identifier: "zh_Hans_CN")
        return f.string(from: day)
    }

    var body: some View {
        NavigationStack {
            List {
                if words.isEmpty {
                    Section {
                        Text("暂无词条，请到「导入」手动添加或从教材批量导入。")
                            .foregroundStyle(.secondary)
                    }
                } else if filteredWords.isEmpty {
                    Section {
                        Text("没有匹配的词条，请换个关键词试试。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(dateSections, id: \.day) { section in
                        Section(sectionTitle(for: section.day)) {
                            ForEach(section.items) { word in
                                NavigationLink {
                                    EditWordView(word: word)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(word.spanish)
                                            .font(.headline)
                                        Text(word.chinese)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        if let u = word.unit {
                                            Text(u.title)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                            .onDelete { offsets in
                                deleteWords(at: offsets, in: section.items)
                            }
                        }
                    }
                }
            }
            .navigationTitle("词库")
            .searchable(text: $searchText, prompt: "搜索西语或中文")
        }
    }

    private func deleteWords(at offsets: IndexSet, in items: [WordEntry]) {
        for index in offsets {
            let w = items[index]
            if let r = w.review {
                modelContext.delete(r)
            }
            modelContext.delete(w)
        }
        try? modelContext.save()
    }
}
