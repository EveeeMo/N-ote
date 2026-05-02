import Foundation
import SwiftData

enum SeedDataService {
    private static let seededKey = "app.didSeedBundledUnits.v1"

    /// 首次启动写入示例词表；若已标记「已种子」但 **WordEntry 为 0**（旧版未 save 等），强制重导 `units.json`，避免永久空库。
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        do {
            let wordCount = try context.fetch(FetchDescriptor<WordEntry>()).count
            let alreadySeeded = UserDefaults.standard.bool(forKey: seededKey)

            if wordCount == 0 {
                try importBundledJSON(named: "units", context: context)
                try DataRefresh.afterImportMutation(context: context)
                UserDefaults.standard.set(true, forKey: seededKey)
                return
            }

            if alreadySeeded { return }

            try importBundledJSON(named: "units", context: context)
            try DataRefresh.afterImportMutation(context: context)
            UserDefaults.standard.set(true, forKey: seededKey)
        } catch {
            print("SeedDataService.seedIfNeeded error: \(error)")
        }
    }

    /// Re-import bundled JSON (debug / reset). Merges by stableId upsert.
    @MainActor
    static func reseedFromBundle(context: ModelContext) throws {
        try importBundledJSON(named: "units", context: context)
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    @MainActor
    static func importBundledJSON(named name: String, context: ModelContext) throws {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "BundledUnits")
            ?? Bundle.main.url(forResource: name, withExtension: "json")
        else {
            throw ImportError.missingFile
        }
        let data = try Data(contentsOf: url)
        let units = try JSONDecoder().decode([BundledUnitDTO].self, from: data)
        try ImportService.upsertUnits(units, context: context)
    }
}
