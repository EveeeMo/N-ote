import Foundation

/// DELE A1–B2 词库：优先使用「已下载」到 Application Support 的副本，否则回退到 App 内置包。
enum DELEPackStorage {
    static let packBaseNames = ["dele_a1", "dele_a2", "dele_b1", "dele_b2"]

    static func isDELEPack(_ bundleFileName: String) -> Bool {
        packBaseNames.contains(bundleFileName)
    }

    static var packsDirectory: URL {
        let bid = Bundle.main.bundleIdentifier ?? "MemorizeSpanish"
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(bid, isDirectory: true).appendingPathComponent("DELEPacks", isDirectory: true)
    }

    static func downloadedFileURL(bundleFileName: String) -> URL {
        packsDirectory.appendingPathComponent("\(bundleFileName).json")
    }

    static func hasDownloadedCopy(bundleFileName: String) -> Bool {
        FileManager.default.fileExists(atPath: downloadedFileURL(bundleFileName: bundleFileName).path)
    }

    /// 已下载优先，否则内置 Bundle。
    static func loadPackData(bundleFileName: String) throws -> Data {
        let dl = downloadedFileURL(bundleFileName: bundleFileName)
        if FileManager.default.fileExists(atPath: dl.path) {
            return try Data(contentsOf: dl)
        }
        guard let url = Bundle.main.url(forResource: bundleFileName, withExtension: "json", subdirectory: "BuiltinBooks")
            ?? Bundle.main.url(forResource: bundleFileName, withExtension: "json")
        else {
            throw ImportError.missingFile
        }
        return try Data(contentsOf: url)
    }

    /// 将内置词库复制到本机（「下载」的默认实现）。
    static func installFromBundle(bundleFileName: String) throws {
        guard let src = Bundle.main.url(forResource: bundleFileName, withExtension: "json", subdirectory: "BuiltinBooks")
            ?? Bundle.main.url(forResource: bundleFileName, withExtension: "json")
        else {
            throw ImportError.missingFile
        }
        try FileManager.default.createDirectory(at: packsDirectory, withIntermediateDirectories: true)
        let dest = downloadedFileURL(bundleFileName: bundleFileName)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: src, to: dest)
    }

    static func removeDownloadedCopy(bundleFileName: String) throws {
        let dest = downloadedFileURL(bundleFileName: bundleFileName)
        guard FileManager.default.fileExists(atPath: dest.path) else { return }
        try FileManager.default.removeItem(at: dest)
    }

    /// 从网络拉取完整词库 JSON（与内置结构相同：`[BundledUnitDTO]`）。
    @MainActor
    static func downloadFromRemote(bundleFileName: String, url: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw ImportError.invalidPayload
        }
        _ = try JSONDecoder().decode([BundledUnitDTO].self, from: data)
        try FileManager.default.createDirectory(at: packsDirectory, withIntermediateDirectories: true)
        let dest = downloadedFileURL(bundleFileName: bundleFileName)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try data.write(to: dest, options: [.atomic])
    }

    static func totalWordCount(bundleFileName: String) throws -> Int {
        let data = try loadPackData(bundleFileName: bundleFileName)
        let units = try JSONDecoder().decode([BundledUnitDTO].self, from: data)
        return units.reduce(0) { $0 + $1.words.count }
    }
}
