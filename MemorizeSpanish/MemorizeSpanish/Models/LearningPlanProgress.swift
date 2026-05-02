import Foundation
import SwiftData

/// DELE 等「按计划学新词」的进度：每个 `planId`（如 dele_a1）一条。
@Model
final class LearningPlanProgress {
    @Attribute(.unique) var planId: String
    /// 下一待学组的序号（0-based），等于已学完组数。
    var nextGroupIndex: Int
    /// 逻辑日当天 0 点；用于判断 `groupsCompletedToday` 是否仍有效。
    var lastGroupCountDayStart: Date?
    /// 当前逻辑日内已完成的组数（跨日由 `LearningPlanService` 归零）。
    var groupsCompletedToday: Int

    init(
        planId: String,
        nextGroupIndex: Int = 0,
        lastGroupCountDayStart: Date? = nil,
        groupsCompletedToday: Int = 0
    ) {
        self.planId = planId
        self.nextGroupIndex = nextGroupIndex
        self.lastGroupCountDayStart = lastGroupCountDayStart
        self.groupsCompletedToday = groupsCompletedToday
    }
}
