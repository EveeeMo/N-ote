import Foundation
import SwiftData

enum LearningPlanService {
    /// 取或创建某计划的进度，并校正「今日组数」跨日归零。
    @MainActor
    static func existingOrCreateProgress(planId: String, context: ModelContext) throws -> LearningPlanProgress {
        let pid = planId
        let fetch = FetchDescriptor<LearningPlanProgress>(predicate: #Predicate<LearningPlanProgress> { $0.planId == pid })
        if let p = try context.fetch(fetch).first {
            normalizeDailyCount(p)
            return p
        }
        let p = LearningPlanProgress(planId: planId)
        context.insert(p)
        normalizeDailyCount(p)
        try context.save()
        return p
    }

    /// 若换日则把 `groupsCompletedToday` 置 0。
    static func normalizeDailyCount(_ p: LearningPlanProgress) {
        let today = AppTime.startOfLogicalToday
        if let last = p.lastGroupCountDayStart, Calendar.current.isDate(last, inSameDayAs: today) {
            return
        }
        p.groupsCompletedToday = 0
        p.lastGroupCountDayStart = today
    }

    /// 当前计划下待学的下一组；已全部学完则 `nil`。
    @MainActor
    static func nextGroupUnit(planId: String, bundleFileName: String, context: ModelContext) throws -> BundledUnitDTO? {
        let units = try BuiltinTextbookService.loadUnits(bundleFileName: bundleFileName)
        guard !units.isEmpty else { return nil }
        let sorted = units.sorted { $0.sortOrder < $1.sortOrder }
        let p = try existingOrCreateProgress(planId: planId, context: context)
        guard p.nextGroupIndex < sorted.count else { return nil }
        return sorted[p.nextGroupIndex]
    }

    static func totalGroupCount(bundleFileName: String) throws -> Int {
        try BuiltinTextbookService.loadUnits(bundleFileName: bundleFileName).count
    }

    /// 将本组写入词库、推进进度、刷新界面。
    @MainActor
    static func commitCompletedGroup(unit: BundledUnitDTO, planId: String, context: ModelContext) throws {
        try ImportService.upsertUnits([unit], context: context)
        try DataRefresh.afterImportMutation(context: context)
        let p = try existingOrCreateProgress(planId: planId, context: context)
        p.nextGroupIndex += 1
        normalizeDailyCount(p)
        p.groupsCompletedToday += 1
        try context.save()
    }
}
