import SwiftData
import SwiftUI
import UserNotifications

struct DebugMenuView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var offset = AppTime.debugDayOffset
    @State private var message: String?
    @State private var dueCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("模拟日期") {
                    Stepper("日偏移：\(offset)", value: $offset, in: -7 ... 14)
                        .onChange(of: offset) { _, v in
                            AppTime.debugDayOffset = v
                            refreshDue()
                        }
                    Text("用于验证「今日待复习」队列，不改变系统时间。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("数据") {
                    Button("合并重复词条（西语相同）") {
                        do {
                            try DedupeService.backfillAndMerge(context: modelContext)
                            try modelContext.save()
                            DataRefresh.notify(modelContext: modelContext)
                            message = "已按西语字面去重合并"
                            refreshDue()
                        } catch {
                            message = "失败：\(error.localizedDescription)"
                        }
                    }
                    Button("重新导入内置示例词表") {
                        do {
                            try SeedDataService.reseedFromBundle(context: modelContext)
                            try DataRefresh.afterImportMutation(context: modelContext)
                            message = "已重新合并内置 JSON"
                            refreshDue()
                        } catch {
                            message = "失败：\(error.localizedDescription)"
                        }
                    }
                    Button("清除模拟日偏移") {
                        offset = 0
                        AppTime.debugDayOffset = 0
                        refreshDue()
                    }
                }

                Section("通知") {
                    Button("发送一条测试通知（约 3 秒后）") {
                        scheduleTestNotification()
                        message = "已安排测试通知"
                    }
                }

                Section("队列") {
                    Text("当前逻辑今日待复习：\(dueCount) 条")
                        .font(.subheadline)
                }

                if let message {
                    Section {
                        Text(message)
                    }
                }
            }
            .navigationTitle("调试")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { refreshDue() }
        }
    }

    private func refreshDue() {
        dueCount = (try? StudyQueueService.dueCount(context: modelContext)) ?? 0
    }

    private func scheduleTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "测试通知"
        content.body = "调试：背诵提醒链路正常"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
