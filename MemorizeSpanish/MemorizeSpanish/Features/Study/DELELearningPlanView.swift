import SwiftData
import SwiftUI

/// DELE 每日新词计划。
struct DELELearningPlanView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var catalog: [BuiltinBookMeta] = []
    @State private var selectedBook: BuiltinBookMeta?
    @State private var totalGroups = 0
    @State private var progress: LearningPlanProgress?
    @State private var loadError: String?
    @State private var sessionUnit: BundledUnitDTO?

    var body: some View {
        Group {
            if let err = loadError {
                ContentUnavailableView("无法加载", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if catalog.isEmpty {
                ProgressView("加载中…")
            } else {
                formContent
            }
        }
        .navigationTitle("DELE 新词计划")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    DELEPacksView()
                } label: {
                    Text("词库")
                }
            }
        }
        .task {
            await loadCatalog()
        }
        .onChange(of: selectedBook) { _, newBook in
            if let b = newBook {
                refreshTotals(for: b)
            }
        }
        .sheet(item: $sessionUnit) { unit in
            NewWordsGroupSessionView(unit: unit, planId: selectedBook?.bookId ?? "")
        }
        .onChange(of: sessionUnit) { _, new in
            if new == nil, let b = selectedBook {
                refreshTotals(for: b)
            }
        }
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            Section("等级") {
                Picker("词库", selection: Binding(
                    get: { selectedBook ?? catalog[0] },
                    set: { selectedBook = $0 }
                )) {
                    ForEach(catalog) { b in
                        Text(b.title).tag(b)
                    }
                }
                .pickerStyle(.navigationLink)

                if let b = selectedBook {
                    Text(b.subtitle ?? "")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if selectedBook != nil, let p = progress {
                Section("进度") {
                    LabeledContent("下一组") {
                        Text("\(min(p.nextGroupIndex + 1, max(totalGroups, 1))) / \(max(totalGroups, 1))")
                            .monospacedDigit()
                    }
                    LabeledContent("今日已学组数") {
                        Text("\(p.groupsCompletedToday)")
                            .monospacedDigit()
                    }
                }

                Section {
                    Button {
                        startNextGroup()
                    } label: {
                        Label("学习本组（约 10 词）", systemImage: "rectangle.stack.badge.plus")
                    }
                    .disabled(p.nextGroupIndex >= totalGroups || totalGroups == 0)

                    Button {
                        startNextGroup()
                    } label: {
                        Label("再学一组", systemImage: "plus.circle")
                    }
                    .disabled(p.nextGroupIndex >= totalGroups || totalGroups == 0)
                }
            }
        }
    }

    private func loadCatalog() async {
        do {
            let books = try BuiltinTextbookService.loadDELECatalog()
            await MainActor.run {
                catalog = books
                if selectedBook == nil {
                    selectedBook = books.first
                }
                if let first = selectedBook ?? books.first {
                    refreshTotals(for: first)
                }
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
            }
        }
    }

    private func refreshTotals(for book: BuiltinBookMeta) {
        totalGroups = (try? LearningPlanService.totalGroupCount(bundleFileName: book.bundleFileName)) ?? 0
        progress = try? LearningPlanService.existingOrCreateProgress(planId: book.bookId, context: modelContext)
    }

    private func startNextGroup() {
        guard let book = selectedBook else { return }
        guard let unit = try? LearningPlanService.nextGroupUnit(
            planId: book.bookId,
            bundleFileName: book.bundleFileName,
            context: modelContext
        ) else { return }
        sessionUnit = unit
    }
}
