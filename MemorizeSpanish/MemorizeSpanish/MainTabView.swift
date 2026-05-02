import Combine
import SwiftData
import SwiftUI

private enum RootTab: Hashable {
    case study
    case library
    case bulkImport
    case settings
}

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("desk.sync.enabled") private var deskSyncEnabled = false
    @AppStorage("desk.sync.baseURL") private var deskSyncBaseURL = ""
    @AppStorage("desk.sync.token") private var deskSyncToken = ""
    @AppStorage("desk.sync.intervalSec") private var deskSyncIntervalSec = 30

    @State private var showDebug = false
    @State private var selectedTab: RootTab = .study
    /// 导入后递增并赋给「学习 / 词库」的 `.id()`，整页销毁重建，强制 `@Query` 重新订阅（比 bump / fetch 更稳）。
    @State private var studyPaneIdentity = UUID()
    @State private var libraryPaneIdentity = UUID()
    @State private var deskSyncLoopTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: $selectedTab) {
            StudyView()
                .id(studyPaneIdentity)
                .tabItem { Label("学习", systemImage: "rectangle.stack.fill") }
                .tag(RootTab.study)

            LibraryView()
                .id(libraryPaneIdentity)
                .tabItem { Label("词库", systemImage: "books.vertical.fill") }
                .tag(RootTab.library)

            ImportView()
                .tabItem { Label("导入", systemImage: "square.and.arrow.down") }
                .tag(RootTab.bulkImport)

            SettingsView(showDebug: $showDebug)
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(RootTab.settings)
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .study || newTab == .library {
                refreshStudyAndLibraryPanes()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: DataRefresh.notification)) { _ in
            refreshStudyAndLibraryPanes()
        }
        .onAppear {
            SeedDataService.seedIfNeeded(context: modelContext)
            try? DedupeService.backfillAndMerge(context: modelContext)
            try? modelContext.save()
            if scenePhase == .active {
                rescheduleDeskSyncForegroundLoop()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                rescheduleDeskSyncForegroundLoop()
            default:
                deskSyncLoopTask?.cancel()
                deskSyncLoopTask = nil
            }
        }
        .onChange(of: deskSyncEnabled) { _, _ in rescheduleDeskSyncForegroundLoop() }
        .onChange(of: deskSyncBaseURL) { _, _ in rescheduleDeskSyncForegroundLoop() }
        .onChange(of: deskSyncToken) { _, _ in rescheduleDeskSyncForegroundLoop() }
        .onChange(of: deskSyncIntervalSec) { _, _ in rescheduleDeskSyncForegroundLoop() }
        .sheet(isPresented: $showDebug) {
            DebugMenuView()
        }
    }

    private func refreshStudyAndLibraryPanes() {
        studyPaneIdentity = UUID()
        libraryPaneIdentity = UUID()
    }

    private func rescheduleDeskSyncForegroundLoop() {
        deskSyncLoopTask?.cancel()
        deskSyncLoopTask = nil
        guard deskSyncEnabled else { return }
        let base = deskSyncBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let tok = deskSyncToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scenePhase == .active, !base.isEmpty, !tok.isEmpty else { return }

        let intervalSeconds = max(15, min(600, deskSyncIntervalSec))

        deskSyncLoopTask = Task { @MainActor in
            DeskSyncBackgroundScheduler.scheduleNext()
            while !Task.isCancelled {
                let msg = await DeskSyncService.syncIfNeeded(baseURL: base, token: tok, context: modelContext)
                if let msg {
                    UserDefaults.standard.set(msg, forKey: "desk.sync.lastSummary")
                }
                DeskSyncBackgroundScheduler.scheduleNext()
                try? await Task.sleep(for: .seconds(intervalSeconds))
            }
        }
    }
}
