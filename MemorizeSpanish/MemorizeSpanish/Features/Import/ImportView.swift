import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<TextbookUnit> { $0.stableId == "unit.manual" },
        sort: \TextbookUnit.sortOrder
    )
    private var manualUnits: [TextbookUnit]

    @State private var showFileImporter = false
    @State private var showFormatHelp = false
    @State private var importBanner: String?
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("手动添加") {
                    if let unit = manualUnits.first {
                        NavigationLink {
                            AddWordView(unit: unit)
                        } label: {
                            Label("添加单词（西语 + 自动释义）", systemImage: "text.badge.plus")
                        }
                    } else {
                        Text("未找到「手动添加」单元，请重启应用以完成初始化。")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("内置教材") {
                    NavigationLink {
                        BuiltinTextbookListView()
                    } label: {
                        Label("走遍西班牙 · 现代西班牙语", systemImage: "books.vertical.fill")
                    }
                }

                Section("DELE 考纲") {
                    NavigationLink {
                        DELEPacksView()
                    } label: {
                        Label("DELE A1–B2 词库", systemImage: "arrow.down.circle")
                    }
                }

                Section("从文件") {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("导入 JSON 词表…", systemImage: "doc.badge.arrow.up")
                    }

                    Button {
                        do {
                            try SeedDataService.reseedFromBundle(context: modelContext)
                            try DataRefresh.afterImportMutation(context: modelContext)
                            let n = (try? modelContext.fetch(FetchDescriptor<WordEntry>()))?.count ?? 0
                            importBanner = "已重新合并内置词表。当前 WordEntry \(n) 条。"
                        } catch {
                            importError = error.localizedDescription
                        }
                    } label: {
                        Label("重新合并内置词表", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button {
                        showFormatHelp = true
                    } label: {
                        Label("JSON 格式说明", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("导入")
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { @MainActor in
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer {
                            if accessing { url.stopAccessingSecurityScopedResource() }
                        }
                        do {
                            try ImportService.importFromFile(url: url, context: modelContext)
                            try DataRefresh.afterImportMutation(context: modelContext)
                            let n = (try? modelContext.fetch(FetchDescriptor<WordEntry>()))?.count ?? 0
                            importBanner = "已从文件导入。当前 WordEntry \(n) 条。"
                        } catch {
                            importError = error.localizedDescription
                        }
                    }
                case .failure(let err):
                    importError = err.localizedDescription
                }
            }
            .alert("导入成功", isPresented: Binding(
                get: { importBanner != nil },
                set: { if !$0 { importBanner = nil } }
            )) {
                Button("好", role: .cancel) { importBanner = nil }
            } message: {
                Text(importBanner ?? "")
            }
            .alert("导入失败", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("好", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .sheet(isPresented: $showFormatHelp) {
                NavigationStack {
                    ScrollView {
                        Text(Self.jsonFormatHelpText)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle("JSON 格式")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showFormatHelp = false }
                        }
                    }
                }
            }
        }
    }

    private static let jsonFormatHelpText = """
    JSON 数组，每项一个单元：

    [
      {
        "unitId": "xixi.a1.u3",
        "title": "走西 A1 第三课",
        "bookId": "xixi",
        "sortOrder": 3,
        "words": [
          {
            "es": "hablar",
            "zh": "说；讲",
            "pos": "verb",
            "lemma": "hablar",
            "note": "可选"
          }
        ]
      }
    ]

    unitId：单元 ID，重复导入会覆盖同单元。
    es / zh / pos 必填；lemma、note 可选。
    相同西语（忽略大小写与首尾空格）会合并。
    pos：noun、verb、adj 等与手动添加一致。
    """
}
