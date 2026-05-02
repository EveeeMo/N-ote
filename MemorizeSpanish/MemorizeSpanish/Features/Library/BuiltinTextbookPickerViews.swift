import SwiftData
import SwiftUI

struct BuiltinTextbookListView: View {
    @State private var books: [BuiltinBookMeta] = []
    @State private var loadError: String?

    var body: some View {
        List {
            if let loadError {
                Text(loadError).foregroundStyle(.red)
            }
            ForEach(books) { book in
                NavigationLink {
                    BuiltinBookUnitsView(book: book)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title)
                            .font(.headline)
                        if let s = book.subtitle {
                            Text(s)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("内置教材")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    private func load() {
        do {
            books = try BuiltinTextbookService.loadCatalog()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct BuiltinBookUnitsView: View {
    @Environment(\.modelContext) private var modelContext

    let book: BuiltinBookMeta

    @State private var units: [BundledUnitDTO] = []
    @State private var selected: Set<String> = []
    @State private var loadError: String?
    @State private var importMessage: String?
    @State private var importError: String?

    var body: some View {
        List(selection: $selected) {
            if let loadError {
                Section {
                    Text(loadError).foregroundStyle(.red)
                }
            }

            Section {
                Text("先勾选单元，再点「选择单词」勾选要导入的词条；也可在菜单里一键导入单元内全部单词。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(units, id: \.unitId) { u in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(u.title)
                            .font(.body)
                        Text("\(u.words.count) 词 · \(u.unitId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .tag(u.unitId)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("全选本册") {
                        selected = Set(units.map(\.unitId))
                    }
                    Button("清除选择") {
                        selected.removeAll()
                    }
                    Divider()
                    Button("直接导入全部所选单元（不筛选单词）") {
                        importSelectedAllWordsInChosenUnits()
                    }
                    .disabled(selected.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                NavigationLink {
                    BuiltinWordSelectionView(units: units.filter { selected.contains($0.unitId) })
                } label: {
                    Text("选择单词")
                }
                .disabled(selected.isEmpty)
            }
        }
        .onAppear { loadUnits() }
        .alert("导入成功", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("好", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .alert("导入失败", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func loadUnits() {
        do {
            units = try BuiltinTextbookService.loadUnits(bundleFileName: book.bundleFileName)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func importSelectedAllWordsInChosenUnits() {
        let toImport = units.filter { selected.contains($0.unitId) }
        guard !toImport.isEmpty else { return }
        do {
            try ImportService.upsertUnits(toImport, context: modelContext)
            try DataRefresh.afterImportMutation(context: modelContext)
            importMessage = "已将 \(toImport.count) 个单元的全部单词合并到你的词库。"
            selected.removeAll()
        } catch {
            importError = error.localizedDescription
        }
    }
}

// MARK: - 按词条筛选导入

struct BuiltinWordSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 已选中的单元（完整 DTO）
    let units: [BundledUnitDTO]

    @State private var selectedWordKeys: Set<String> = []
    @State private var importMessage: String?
    @State private var importError: String?

    private var allWordKeys: [String] {
        units.flatMap { u in
            u.words.map { ImportService.wordStableId(unitId: u.unitId, spanish: $0.es) }
        }
    }

    var body: some View {
        // 不用 List(selection:)，分组 Section 下多选绑定在 SwiftUI 里经常不刷新；改用手动勾选。
        List {
            Section {
                Text("默认已全选，点行可勾选/取消；仅「已勾选」的词条会导入。与词库中已有相同西语时会合并更新释义。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(units, id: \.unitId) { unit in
                Section {
                    ForEach(
                        (0 ..< unit.words.count).map { BuiltinWordRowKey(unitId: unit.unitId, index: $0) },
                        id: \.self
                    ) { row in
                        let w = unit.words[row.index]
                        let key = ImportService.wordStableId(unitId: unit.unitId, spanish: w.es)
                        Button {
                            if selectedWordKeys.contains(key) {
                                selectedWordKeys.remove(key)
                            } else {
                                selectedWordKeys.insert(key)
                            }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: selectedWordKeys.contains(key) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedWordKeys.contains(key) ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(w.es)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(w.zh)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(unit.title)
                }
            }
        }
        .navigationTitle("选择单词")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("全选") {
                        selectedWordKeys = Set(allWordKeys)
                    }
                    Button("全不选") {
                        selectedWordKeys.removeAll()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("导入 (\(selectedWordKeys.count))") {
                    importPickedWords()
                }
                .disabled(selectedWordKeys.isEmpty)
            }
        }
        .onAppear {
            if selectedWordKeys.isEmpty {
                selectedWordKeys = Set(allWordKeys)
            }
        }
        .alert("导入成功", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("好", role: .cancel) {
                importMessage = nil
                dismiss()
            }
        } message: {
            Text(importMessage ?? "")
        }
        .alert("导入失败", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func importPickedWords() {
        var dtos: [BundledUnitDTO] = []
        for u in units {
            let picked = u.words.filter {
                selectedWordKeys.contains(ImportService.wordStableId(unitId: u.unitId, spanish: $0.es))
            }
            guard !picked.isEmpty else { continue }
            dtos.append(BundledUnitDTO(unitId: u.unitId, title: u.title, bookId: u.bookId, sortOrder: u.sortOrder, words: picked))
        }
        guard !dtos.isEmpty else { return }
        do {
            try ImportService.upsertUnits(dtos, context: modelContext)
            try DataRefresh.afterImportMutation(context: modelContext)
            importMessage = "已导入 \(selectedWordKeys.count) 个词条（\(dtos.count) 个单元）。"
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// `ForEach` 在多个 Section 里不能用仅按 `index` 的 id，否则跨单元重复；用单元 id + 词下标保证全局唯一。
private struct BuiltinWordRowKey: Hashable {
    let unitId: String
    let index: Int
}
