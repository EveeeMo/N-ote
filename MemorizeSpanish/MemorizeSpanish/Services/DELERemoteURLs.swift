import Foundation

/// 可选：在 `dele_remote_urls.json` 中为各等级填写 HTTPS 链接，导入页「从网络更新」将拉取该 JSON（格式与内置 `dele_a1.json` 相同）。
enum DELERemoteURLs {
    private struct File: Codable {
        var urls: [String: String]
    }

    static func url(forBundleFileName bundleFileName: String) -> URL? {
        guard let data = loadJSONData(),
              let decoded = try? JSONDecoder().decode(File.self, from: data),
              let s = decoded.urls[bundleFileName]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty,
              let u = URL(string: s),
              u.scheme == "https" || u.scheme == "http"
        else { return nil }
        return u
    }

    private static func loadJSONData() -> Data? {
        guard let url = Bundle.main.url(forResource: "dele_remote_urls", withExtension: "json", subdirectory: "BuiltinBooks")
            ?? Bundle.main.url(forResource: "dele_remote_urls", withExtension: "json")
        else { return nil }
        return try? Data(contentsOf: url)
    }
}
