import Foundation

/// 学习库全量备份文件（与教材 JSON 导入格式不同）。
enum LibraryBackupFormat {
    static let current = "MemorizeSpanish.library.v1"
}

/// 顶层备份文件结构。
struct LibraryBackupFile: Codable {
    var format: String
    var exportedAt: Date
    var exportedFromAppVersion: String?
    var exportedFromBundleId: String?
    /// 非敏感辅助信息，如 `appleUserIdPrefix`、**内测** `testerInviteCode`（供排查；旧备份可无此字段）。
    var metadata: [String: String]?
    /// 与 `UserDefaults` / `@AppStorage` 对齐的字符串键值（如提醒、动词变位偏好）。
    var preferences: [String: String]?
    var units: [TextbookUnitSnap]
    var words: [WordEntrySnap]
    var learningPlans: [LearningPlanProgressSnap]

    struct TextbookUnitSnap: Codable, Sendable {
        var stableId: String
        var title: String
        var bookId: String
        var sortOrder: Int
    }

    struct WordEntrySnap: Codable, Sendable {
        var stableId: String
        var dedupeKey: String
        var spanish: String
        var chinese: String
        var partOfSpeech: String
        var lemma: String?
        var userNote: String
        var createdAt: Date
        var lastActivityAt: Date
        var unitStableId: String?
        var review: ReviewSnap?
    }

    struct ReviewSnap: Codable, Sendable {
        var nextReview: Date
        var intervalDays: Double
        var easeFactor: Double
        var repetitions: Int
    }

    struct LearningPlanProgressSnap: Codable, Sendable {
        var planId: String
        var nextGroupIndex: Int
        var lastGroupCountDayStart: Date?
        var groupsCompletedToday: Int
    }
}
