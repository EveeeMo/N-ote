import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var showDebug: Bool

    @ObservedObject private var tester = TesterAccessService.shared

    /// 与词库同源：用于判断导入是否真正写入 SwiftData（若此处不变，问题在持久化而非 Tab UI）。
    @Query(sort: \WordEntry.createdAt, order: .reverse) private var diagnosticWords: [WordEntry]

    @AppStorage("reminder.enabled") private var reminderEnabled = false
    @AppStorage("reminder.hour") private var reminderHour = 9
    @AppStorage("reminder.minute") private var reminderMinute = 0

    @AppStorage(ConjugationPreferences.storageKey) private var conjugationJSON: String = ""

    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showBackupImporter = false
    @State private var backupMessage: String?
    @State private var pendingBackupData: Data?
    @State private var showBackupReplaceConfirm = false
    @State private var showExportShareSheet = false
    @State private var exportShareURL: URL?
    @State private var debugTapCount = 0
    @State private var testerCodeInput = ""
    @State private var testerCodeMessage: String?

    @AppStorage("desk.sync.enabled") private var deskSyncEnabled = false
    @AppStorage("desk.sync.baseURL") private var deskSyncBaseURL = ""
    @AppStorage("desk.sync.token") private var deskSyncToken = ""
    @AppStorage("desk.sync.intervalSec") private var deskSyncIntervalSec = 30
    @AppStorage("desk.sync.lastSummary") private var deskSyncLastSummary = ""
    @AppStorage("desk.sync.backgroundFetch") private var deskSyncBackgroundFetch = true

    @State private var deskSyncBusy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("内测（邀请码）") {
                    Text("在源码 TesterAccessService 内的 TestInviteCodes 中登记邀请码，重新打 TestFlight/安装包后，把同一串码分发给测试者。用于识别渠道，不能防止他人安装非正式包。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let code = tester.activatedCode {
                        Text("已激活：\(code)")
                            .font(.body.monospaced().bold())
                        Button("清除邀请码", role: .destructive) {
                            testerCodeMessage = nil
                            tester.clearActivation()
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            TextField("输入邀请码", text: $testerCodeInput)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            Button("激活") {
                                testerCodeMessage = nil
                                if tester.tryActivate(testerCodeInput) {
                                    testerCodeMessage = "已激活内测身份。"
                                } else {
                                    testerCodeMessage = "邀请码无效或已变更（请确认你手上的安装包与发码时登记的列表一致）。"
                                }
                            }
                        }
                    }
                    if let testerCodeMessage {
                        Text(testerCodeMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("学习数据") {
                    Text("词库与复习数据使用本机 SwiftData。「词库同步服务」可把你在任意地点浏览器里录入的词合并进「手动添加」（需你自托管带 https 的小服务，见设置里说明）。多设备与换机请继续用「学习库备份」。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("每日提醒") {
                    Toggle("启用本地通知", isOn: $reminderEnabled)
                        .onChange(of: reminderEnabled) { _, on in
                            Task {
                                if on {
                                    let ok = await NotificationService.requestAuthorization()
                                    if ok {
                                        NotificationService.scheduleDailyReminder(hour: reminderHour, minute: reminderMinute)
                                    } else {
                                        reminderEnabled = false
                                    }
                                } else {
                                    NotificationService.cancelDailyReminder()
                                }
                            }
                        }
                    if reminderEnabled {
                        Stepper("小时：\(reminderHour)", value: $reminderHour, in: 0 ... 23)
                            .onChange(of: reminderHour) { _, _ in reschedule() }
                        Stepper("分钟：\(reminderMinute)", value: $reminderMinute, in: 0 ... 59, step: 5)
                            .onChange(of: reminderMinute) { _, _ in reschedule() }
                    }
                }

                Section("自动翻译") {
                    Text("手工添加时的「自动填充中文」使用 MyMemory 公共接口（联网、有频率限制），仅供学习测试；正式上架请替换为合规翻译服务。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("词库同步（自托管）") {
                    Text("在任意地点浏览器录词：把仓库里 DeskManualSync 部署到 Railway / Fly.io 等提供 https 的平台，设置强随机 NOTE_DESK_SYNC_TOKEN，并把持久化目录 data/ 挂到卷（否则重启丢数据）。APP 填云端基础地址（https://你的域名，无结尾斜杠）与同令牌；前台会轮询，并尽量在系统允许时后台刷新。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("前台自动同步", isOn: $deskSyncEnabled)
                    Toggle("后台尝试同步（需系统「后台 App 刷新」)", isOn: $deskSyncBackgroundFetch)
                        .onChange(of: deskSyncBackgroundFetch) { _, _ in
                            DeskSyncBackgroundScheduler.scheduleNext()
                        }
                    TextField("服务基础地址（公网请 https://）", text: $deskSyncBaseURL)
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                        #endif
                    TextField("Bearer 令牌（NOTE_DESK_SYNC_TOKEN）", text: $deskSyncToken)
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        #endif

                    Picker("前台轮询间隔（秒）", selection: $deskSyncIntervalSec) {
                        Text("15").tag(15)
                        Text("30").tag(30)
                        Text("60").tag(60)
                        Text("120").tag(120)
                        Text("300").tag(300)
                    }

                    Button {
                        deskSyncBusy = true
                        Task { @MainActor in
                            defer { deskSyncBusy = false }
                            let hint = await DeskSyncService.syncIfNeeded(
                                baseURL: deskSyncBaseURL,
                                token: deskSyncToken,
                                context: modelContext,
                                force: true
                            )
                            deskSyncLastSummary = hint ?? "已与服务端修订号对齐，暂无新合并。"
                            DeskSyncBackgroundScheduler.scheduleNext()
                        }
                    } label: {
                        if deskSyncBusy {
                            ProgressView("同步中…")
                        } else {
                            Label("立即从服务端同步", systemImage: "arrow.down.doc")
                        }
                    }
                    .disabled(deskSyncBusy)

                    Button("清除本地修订进度标记（下次静默同步视作有新版本）", role: .none) {
                        DeskSyncService.clearLocalRevisionWatermark()
                        deskSyncLastSummary = "已清除本地标记。"
                    }

                    if !deskSyncLastSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(deskSyncLastSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("说明：服务端删除某词不会自动删掉手机里已并入的词条；令牌与 http 明文等价，勿泄露部署地址。真·多账户云同步需以后再接 Apple 账号 / CloudKit。")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }

                Section("动词变位") {
                    Text("选择在全 app（词库中的动词预览、学习页变位表等）中展示哪些时态。未保存过偏好时，默认展示现在时、肯定命令式、虚拟现在时。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(SpanishTense.settingsOrder, id: \.rawValue) { tense in
                        Toggle(
                            isOn: Binding(
                                get: {
                                    ConjugationPreferences
                                        .enabledTenses(fromJSONString: conjugationJSON.isEmpty ? nil : conjugationJSON)
                                        .map(\.rawValue)
                                        .contains(tense.rawValue)
                                },
                                set: { on in
                                    var current = Set(
                                        ConjugationPreferences
                                            .enabledTenses(fromJSONString: conjugationJSON.isEmpty ? nil : conjugationJSON)
                                            .map(\.rawValue)
                                    )
                                    if on {
                                        current.insert(tense.rawValue)
                                    } else {
                                        current.remove(tense.rawValue)
                                    }
                                    let ordered = SpanishTense.settingsOrder.filter { current.contains($0.rawValue) }
                                    let raw = ordered.map(\.rawValue)
                                    if let data = try? JSONEncoder().encode(raw),
                                       let str = String(data: data, encoding: .utf8)
                                    {
                                        conjugationJSON = str
                                    }
                                }
                            )
                        ) {
                            Text(tense.rawValue)
                        }
                    }
                }

                Section("数据诊断") {
                    Text("WordEntry 总数：\(diagnosticWords.count)")
                        .font(.body.monospacedDigit())
                    Text("启动时会自动回补：若曾标记「已种子」但库里0 条，会重导内置 units.json。导入后若仍长期为 0，请看 Xcode 控制台是否有 SeedDataService / Import 报错。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("学习库备份") {
                    Text("与下方「词表」中的教材 JSON 不同：此处导出/恢复的是你在本机的全部学习数据（单元、词条、复习状态、学习计划进度及部分设置）。卸载 App 会清空数据，换机或大版本前请先导出备份。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("导出学习库…") {
                        Task { @MainActor in
                            backupMessage = nil
                            do {
                                let data = try LibraryBackupService.exportLibraryData(context: modelContext)
                                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                                let url = FileManager.default.temporaryDirectory
                                    .appendingPathComponent("MemorizeSpanish-library-\(stamp).json")
                                try data.write(to: url, options: .atomic)
                                exportShareURL = url
                                showExportShareSheet = true
                            } catch {
                                backupMessage = "导出失败：\(error.localizedDescription)"
                            }
                        }
                    }
                    Button("从备份恢复…") { showBackupImporter = true }
                    if let backupMessage {
                        Text(backupMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("词表") {
                    Text("从 JSON 导入教材词表（与「学习库备份」不是同一格式）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("导入 JSON…") { showImporter = true }
                    if let importMessage {
                        Text(importMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("关于") {
                    Text("Ñote · 首版")
                    Text("内置示例单元仅供演示；教材词表请自行确认版权。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                Section("开发者") {
                    Button("打开调试菜单") { showDebug = true }
                }
                #endif

                Section {
                    Text(appVersionString)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .onTapGesture {
                            debugTapCount += 1
                            if debugTapCount >= 5 {
                                debugTapCount = 0
                                showDebug = true
                            }
                        }
                }
            }
            .navigationTitle("设置")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    Task { @MainActor in
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        do {
                            try ImportService.importFromFile(url: url, context: modelContext)
                            try DataRefresh.afterImportMutation(context: modelContext)
                            let n = (try? modelContext.fetch(FetchDescriptor<WordEntry>()))?.count ?? 0
                            importMessage = "导入成功，当前 WordEntry \(n) 条"
                        } catch {
                            importMessage = "导入失败：\(error.localizedDescription)"
                        }
                    }
                case let .failure(err):
                    importMessage = err.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    Task { @MainActor in
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        do {
                            let data = try Data(contentsOf: url)
                            guard LibraryBackupService.isLibraryBackupFile(data: data) else {
                                backupMessage = "所选文件不是本应用的学习库备份（或版本过旧）。请使用「导出学习库」生成的文件。"
                                return
                            }
                            pendingBackupData = data
                            showBackupReplaceConfirm = true
                        } catch {
                            backupMessage = "无法读取文件：\(error.localizedDescription)"
                        }
                    }
                case let .failure(err):
                    backupMessage = err.localizedDescription
                }
            }
            .sheet(isPresented: $showExportShareSheet, onDismiss: { exportShareURL = nil }) {
                if let url = exportShareURL {
                    NavigationStack {
                        Form {
                            ShareLink(item: url) {
                                Label("分享或存储到「文件」", systemImage: "square.and.arrow.up")
                            }
                        }
                        .navigationTitle("导出备份")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("完成") { showExportShareSheet = false }
                            }
                        }
                    }
                }
            }
            .alert("从备份恢复？", isPresented: $showBackupReplaceConfirm) {
                Button("取消", role: .cancel) {
                    pendingBackupData = nil
                }
                Button("替换当前数据", role: .destructive) {
                    Task { @MainActor in
                        guard let data = pendingBackupData else { return }
                        pendingBackupData = nil
                        do {
                            try LibraryBackupService.importLibraryData(data: data, context: modelContext)
                            let n = (try? modelContext.fetch(FetchDescriptor<WordEntry>()))?.count ?? 0
                            backupMessage = "恢复成功，当前 WordEntry \(n) 条"
                        } catch {
                            backupMessage = "恢复失败：\(error.localizedDescription)"
                        }
                    }
                }
            } message: {
                Text("将删除本机全部词库、复习进度与学习计划进度，且无法撤销。请确认备份文件来源正确。")
            }
        }
    }

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "版本 \(v) (\(b)) · 连点五次打开调试"
    }

    private func reschedule() {
        guard reminderEnabled else { return }
        NotificationService.scheduleDailyReminder(hour: reminderHour, minute: reminderMinute)
    }
}
