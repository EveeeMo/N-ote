import Foundation
import SwiftData

/// 写入 SwiftData 后广播，供 `MainTabView` 递增 `dataStoreBump` 并传给词库 / 学习子视图触发 `fetch`。
enum DataRefresh {
    static let notification = Notification.Name("MemorizeSpanish.modelDataDidChange")

    ///主线程上同步发通知，避免 `async` 晚于用户切 Tab 导致仍读到旧数据。
    static func notify(modelContext: ModelContext? = nil) {
        modelContext?.processPendingChanges()
        let post = {
            NotificationCenter.default.post(name: notification, object: nil)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    /// 导入或批量改库后统一收尾：`save` → 去重合并 → 再 `save`（合并会删对象，缺第二次落盘时其他界面 `fetch` 可能仍像旧数据）。
    @MainActor
    static func afterImportMutation(context: ModelContext) throws {
        try context.save()
        try DedupeService.backfillAndMerge(context: context)
        try context.save()
        #if DEBUG
        let n = (try? context.fetch(FetchDescriptor<WordEntry>()))?.count ?? -1
        let r = (try? context.fetch(FetchDescriptor<ReviewItem>()))?.count ?? -1
        print("[MemorizeSpanish] afterImportMutation WordEntry=\(n) ReviewItem=\(r)")
        #endif
        notify(modelContext: context)
    }
}
