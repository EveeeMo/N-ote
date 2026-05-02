import Foundation
import SwiftData

enum LibraryBackupError: LocalizedError {
    case invalidOrUnknownFormat
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidOrUnknownFormat:
            return "不是本应用的学习库备份文件，或版本过旧。"
        case .decodeFailed:
            return "备份文件解析失败。"
        }
    }
}

enum LibraryBackupService {
    /// 用于在导入前区分「教材 JSON」与「学习库备份」。
    static func isLibraryBackupFile(data: Data) -> Bool {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let file = try? dec.decode(LibraryBackupFile.self, from: data) else { return false }
        return file.format == LibraryBackupFormat.current
    }

    private static let preferenceKeysToBackup: [String] = [
        "reminder.enabled",
        "reminder.hour",
        "reminder.minute",
        ConjugationPreferences.storageKey,
    ]

    /// 导出为 JSON `Data`，供写入文件或分享。
    @MainActor
    static func exportLibraryData(context: ModelContext) throws -> Data {
        let units = try context.fetch(FetchDescriptor<TextbookUnit>(sortBy: [SortDescriptor(\.stableId)]))
        let words = try context.fetch(FetchDescriptor<WordEntry>(sortBy: [SortDescriptor(\.stableId)]))

        let unitSnaps: [LibraryBackupFile.TextbookUnitSnap] = units.map {
            LibraryBackupFile.TextbookUnitSnap(
                stableId: $0.stableId,
                title: $0.title,
                bookId: $0.bookId,
                sortOrder: $0.sortOrder
            )
        }

        var wordSnaps: [LibraryBackupFile.WordEntrySnap] = []
        wordSnaps.reserveCapacity(words.count)
        for w in words {
            let unitId = w.unit?.stableId
            var rev: LibraryBackupFile.ReviewSnap?
            if let r = w.review {
                rev = LibraryBackupFile.ReviewSnap(
                    nextReview: r.nextReview,
                    intervalDays: r.intervalDays,
                    easeFactor: r.easeFactor,
                    repetitions: r.repetitions
                )
            }
            wordSnaps.append(
                LibraryBackupFile.WordEntrySnap(
                    stableId: w.stableId,
                    dedupeKey: w.dedupeKey,
                    spanish: w.spanish,
                    chinese: w.chinese,
                    partOfSpeech: w.partOfSpeech,
                    lemma: w.lemma,
                    userNote: w.userNote,
                    createdAt: w.createdAt,
                    lastActivityAt: w.lastActivityAt,
                    unitStableId: unitId,
                    review: rev
                )
            )
        }

        let plans = try context.fetch(FetchDescriptor<LearningPlanProgress>(sortBy: [SortDescriptor(\.planId)]))
        let planSnaps = plans.map {
            LibraryBackupFile.LearningPlanProgressSnap(
                planId: $0.planId,
                nextGroupIndex: $0.nextGroupIndex,
                lastGroupCountDayStart: $0.lastGroupCountDayStart,
                groupsCompletedToday: $0.groupsCompletedToday
            )
        }

        var prefs: [String: String] = [:]
        let ud = UserDefaults.standard
        for k in preferenceKeysToBackup {
            guard let v = ud.object(forKey: k) else { continue }
            if let b = v as? Bool {
                prefs[k] = b ? "true" : "false"
            } else if let i = v as? Int {
                prefs[k] = "\(i)"
            } else if let s = v as? String {
                prefs[k] = s
            } else {
                prefs[k] = "\(v)"
            }
        }

        var meta: [String: String] = [:]
        if let p = AppleAccountManager.shared.userIdentifier.map({ String($0.prefix(8)) }) {
            meta["appleUserIdPrefix"] = p
        }
        if let c = TesterAccessService.shared.activatedCode {
            meta["testerInviteCode"] = c
        }

        let file = LibraryBackupFile(
            format: LibraryBackupFormat.current,
            exportedAt: Date(),
            exportedFromAppVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            exportedFromBundleId: Bundle.main.bundleIdentifier,
            metadata: meta.isEmpty ? nil : meta,
            preferences: prefs.isEmpty ? nil : prefs,
            units: unitSnaps,
            words: wordSnaps,
            learningPlans: planSnaps
        )

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(file)
    }

    /// 全量替换：删除现有 SwiftData 再写入备份（需已在 UI 中确认）。
    @MainActor
    static func importLibraryData(data: Data, context: ModelContext) throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let file: LibraryBackupFile
        do {
            file = try dec.decode(LibraryBackupFile.self, from: data)
        } catch {
            throw LibraryBackupError.decodeFailed
        }
        guard file.format == LibraryBackupFormat.current else {
            throw LibraryBackupError.invalidOrUnknownFormat
        }

        try wipeAllUserData(context: context)

        var unitByStable: [String: TextbookUnit] = [:]
        for s in file.units {
            let u = TextbookUnit(stableId: s.stableId, title: s.title, bookId: s.bookId, sortOrder: s.sortOrder)
            context.insert(u)
            unitByStable[s.stableId] = u
        }

        for s in file.words {
            let unit = s.unitStableId.flatMap { unitByStable[$0] }
            let entry = WordEntry(
                stableId: s.stableId,
                spanish: s.spanish,
                chinese: s.chinese,
                partOfSpeech: s.partOfSpeech,
                lemma: s.lemma,
                userNote: s.userNote,
                createdAt: s.createdAt,
                lastActivityAt: s.lastActivityAt,
                unit: unit,
                dedupeKey: s.dedupeKey
            )
            context.insert(entry)
            if let rs = s.review {
                let r = ReviewItem(
                    nextReview: rs.nextReview,
                    intervalDays: rs.intervalDays,
                    easeFactor: rs.easeFactor,
                    repetitions: rs.repetitions,
                    word: entry
                )
                entry.review = r
                context.insert(r)
            }
        }

        for p in file.learningPlans {
            let lp = LearningPlanProgress(
                planId: p.planId,
                nextGroupIndex: p.nextGroupIndex,
                lastGroupCountDayStart: p.lastGroupCountDayStart,
                groupsCompletedToday: p.groupsCompletedToday
            )
            context.insert(lp)
        }

        if let prefs = file.preferences {
            let ud = UserDefaults.standard
            for (k, v) in prefs {
                switch k {
                case "reminder.enabled":
                    ud.set(v == "true" || v == "1", forKey: k)
                case "reminder.hour", "reminder.minute":
                    if let i = Int(v) { ud.set(i, forKey: k) }
                case ConjugationPreferences.storageKey:
                    ud.set(v, forKey: k)
                default:
                    break
                }
            }
        }

        try context.save()
        try DataRefresh.afterImportMutation(context: context)
    }

    @MainActor
    private static func wipeAllUserData(context: ModelContext) throws {
        let words = try context.fetch(FetchDescriptor<WordEntry>())
        for w in words {
            context.delete(w)
        }
        let units = try context.fetch(FetchDescriptor<TextbookUnit>())
        for u in units {
            context.delete(u)
        }
        let plans = try context.fetch(FetchDescriptor<LearningPlanProgress>())
        for p in plans {
            context.delete(p)
        }
        try context.save()
    }
}
