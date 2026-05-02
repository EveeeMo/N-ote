import BackgroundTasks
import Foundation
import SwiftData

/// 在系统允许时低频拉取云端词库（不能保证精确间隔；需在系统设置里打开「后台 App 刷新」）。
enum DeskSyncBackgroundScheduler {
    static let taskIdentifier = "com.eve.memorizespanish.desk-sync-refresh"

    private static let backgroundFetchDefaultsKey = "desk.sync.backgroundFetch"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    /// 在打开自动同步或每次前台拉取之后调用，向系统申请下一次后台机会（若用户关闭「后台同步」则跳过）。
    static func scheduleNext() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "desk.sync.enabled") else { return }
        let bgOn = (defaults.object(forKey: backgroundFetchDefaultsKey) as? Bool) ?? true
        guard bgOn else { return }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[DeskSyncBG] submit failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let lock = NSLock()
        var finished = false

        func finish(success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            scheduleNext()
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            finish(success: false)
        }

        Task { @MainActor in
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: "desk.sync.enabled") else {
                finish(success: true)
                return
            }
            let bgOn = (defaults.object(forKey: backgroundFetchDefaultsKey) as? Bool) ?? true
            guard bgOn else {
                finish(success: true)
                return
            }
            let base = defaults.string(forKey: "desk.sync.baseURL") ?? ""
            let token = defaults.string(forKey: "desk.sync.token") ?? ""
            let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTok = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBase.isEmpty, !trimmedTok.isEmpty else {
                finish(success: true)
                return
            }

            do {
                let container = try ModelContainer(
                    for: TextbookUnit.self, WordEntry.self, ReviewItem.self, LearningPlanProgress.self
                )
                let context = ModelContext(container)
                _ = await DeskSyncService.syncIfNeeded(
                    baseURL: trimmedBase,
                    token: trimmedTok,
                    context: context
                )
                finish(success: true)
            } catch {
                finish(success: false)
            }
        }
    }
}
