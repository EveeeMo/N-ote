import SwiftUI

/// 管理 DELE A1–B2 词库：下载到本机（复制内置）或从网络更新（需在 `dele_remote_urls.json` 填写 URL）。
struct DELEPacksView: View {
    @State private var books: [BuiltinBookMeta] = []
    @State private var loadError: String?
    @State private var wordCounts: [String: Int] = [:]
    @State private var busyPack: String?
    @State private var busyRemoteFor: String?
    @State private var banner: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView("无法加载", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if books.isEmpty {
                ProgressView("加载中…")
            } else {
                Form {
                    ForEach(books) { book in
                        Section(book.title) {
                            LabeledContent("词条数") {
                                Text("\(wordCounts[book.bundleFileName] ?? 0)")
                                    .monospacedDigit()
                            }
                            if DELEPackStorage.hasDownloadedCopy(bundleFileName: book.bundleFileName) {
                                Label("已下载到本机", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            } else {
                                Label("未下载（当前使用内置词库）", systemImage: "icloud")
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                Task { await installFromBundle(book) }
                            } label: {
                                if busyPack == book.bundleFileName {
                                    ProgressView()
                                } else {
                                    Label("下载到本机", systemImage: "arrow.down.circle")
                                }
                            }
                            .disabled(busyPack != nil || busyRemoteFor != nil)

                            if let remote = DELERemoteURLs.url(forBundleFileName: book.bundleFileName) {
                                Button {
                                    Task { await downloadRemote(book, url: remote) }
                                } label: {
                                    if busyRemoteFor == book.bundleFileName {
                                        ProgressView()
                                    } else {
                                        Label("从网络更新", systemImage: "arrow.down.circle.badge.clock")
                                    }
                                }
                                .disabled(busyPack != nil || busyRemoteFor != nil)
                            }

                            if DELEPackStorage.hasDownloadedCopy(bundleFileName: book.bundleFileName) {
                                Button(role: .destructive) {
                                    Task { await removeDownloaded(book) }
                                } label: {
                                    Label("删除本机副本", systemImage: "trash")
                                }
                                .disabled(busyPack != nil || busyRemoteFor != nil)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("DELE 词库")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .alert("提示", isPresented: Binding(
            get: { banner != nil },
            set: { if !$0 { banner = nil } }
        )) {
            Button("好", role: .cancel) { banner = nil }
        } message: {
            Text(banner ?? "")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func load() async {
        do {
            books = try BuiltinTextbookService.loadDELECatalog()
            var counts: [String: Int] = [:]
            for b in books {
                counts[b.bundleFileName] = try DELEPackStorage.totalWordCount(bundleFileName: b.bundleFileName)
            }
            wordCounts = counts
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func installFromBundle(_ book: BuiltinBookMeta) async {
        busyPack = book.bundleFileName
        defer { busyPack = nil }
        do {
            try DELEPackStorage.installFromBundle(bundleFileName: book.bundleFileName)
            wordCounts[book.bundleFileName] = try DELEPackStorage.totalWordCount(bundleFileName: book.bundleFileName)
            banner = "「\(book.title)」已保存到本机。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func downloadRemote(_ book: BuiltinBookMeta, url: URL) async {
        busyRemoteFor = book.bundleFileName
        defer { busyRemoteFor = nil }
        do {
            try await DELEPackStorage.downloadFromRemote(bundleFileName: book.bundleFileName, url: url)
            wordCounts[book.bundleFileName] = try DELEPackStorage.totalWordCount(bundleFileName: book.bundleFileName)
            banner = "「\(book.title)」已从网络更新。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func removeDownloaded(_ book: BuiltinBookMeta) async {
        busyPack = book.bundleFileName
        defer { busyPack = nil }
        do {
            try DELEPackStorage.removeDownloadedCopy(bundleFileName: book.bundleFileName)
            wordCounts[book.bundleFileName] = try DELEPackStorage.totalWordCount(bundleFileName: book.bundleFileName)
            banner = "已删除本机副本，将使用内置词库。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
