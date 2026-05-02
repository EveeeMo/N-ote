import Foundation
import SwiftData

private struct DeskSyncPayload: Decodable {
    let revision: Int
    let units: [BundledUnitDTO]
}

enum DeskSyncService {
    private static let remoteRevisionKey = "desk.sync.remoteRevision"

    enum PullError: LocalizedError {
        case invalidBaseURL
        case unauthorized
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "同步服务地址无效。"
            case .unauthorized:
                return "令牌无效或服务不可达。"
            case let .badStatus(c):
                return "请求失败（HTTP \(c)）。"
            }
        }
    }

    static func clearLocalRevisionWatermark() {
        UserDefaults.standard.removeObject(forKey: remoteRevisionKey)
    }

    private static func currentRemoteRevision() -> Int {
        UserDefaults.standard.integer(forKey: remoteRevisionKey)
    }

    private static func setRemoteRevision(_ v: Int) {
        UserDefaults.standard.set(v, forKey: remoteRevisionKey)
    }

    /// - Returns: 需要展示给用户的说明；`nil` 表示服务端修订号未变已跳过（静默）。
    @MainActor
    static func syncIfNeeded(
        baseURL: String,
        token: String,
        context: ModelContext,
        force: Bool = false
    ) async -> String? {
        guard let base = validatedBaseURLString(baseURL) else {
            let hint = insecureHTTPHintIfNeeded(baseURL)
            return hint ?? "同步服务地址无效，请填写完整的 https:// 地址（公网）或本机/私网 http 地址。"
        }
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            return "请填写与服务端环境变量 NOTE_DESK_SYNC_TOKEN 一致的 Bearer 令牌。"
        }

        do {
            let payload = try await Task.detached {
                try await Self.fetchPayload(base: base, token: t)
            }.value

            if !force && payload.revision <= Self.currentRemoteRevision() {
                return nil
            }

            guard !payload.units.isEmpty else {
                return "服务端返回空词表。"
            }

            try ImportService.upsertUnits(payload.units, context: context)
            try DataRefresh.afterImportMutation(context: context)
            Self.setRemoteRevision(payload.revision)

            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "zh_Hans_CN")
            fmt.dateFormat = "HH:mm:ss"
            return "已合并「手动添加」词库（服务端 rev \(payload.revision)）·\(fmt.string(from: Date()))"
        } catch let e as PullError {
            return e.localizedDescription
        } catch {
            return error.localizedDescription
        }
    }

    /// 公网须 `https`；`http` 仅允许本机与常见私网，避免误把明文服务暴露到互联网上。
    nonisolated private static func validatedBaseURLString(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty, let u = URL(string: s) else { return nil }
        let scheme = u.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { return nil }
        if scheme == "http" {
            guard let host = u.host?.lowercased(), hostAllowsInsecureHTTP(host) else { return nil }
        }
        return s
    }

    nonisolated private static func insecureHTTPHintIfNeeded(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard let u = URL(string: s), u.scheme?.lowercased() == "http", let h = u.host?.lowercased() else { return nil }
        guard !hostAllowsInsecureHTTP(h) else { return nil }
        return "互联网同步请使用以 https:// 开头的地址。当前 http 仅限本机或常见私网（如 192.168.x.x）；请把词库服务托管到带 TLS 的云端。"
    }

    nonisolated private static func hostAllowsInsecureHTTP(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "[::1]" { return true }
        if host.hasPrefix("192.168.") { return true }
        if host.hasPrefix("10.") { return true }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16 ... 31).contains(second) {
                return true
            }
        }
        return false
    }

    nonisolated private static func fetchPayload(base: String, token: String) async throws -> DeskSyncPayload {
        guard let url = URL(string: base + "/api/sync/unit") else { throw PullError.invalidBaseURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 401 { throw PullError.unauthorized }
            if !(200 ... 299).contains(http.statusCode) { throw PullError.badStatus(http.statusCode) }
        }
        return try JSONDecoder().decode(DeskSyncPayload.self, from: data)
    }
}
