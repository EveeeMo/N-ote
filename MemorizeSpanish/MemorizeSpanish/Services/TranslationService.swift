import Foundation

protocol TranslationService {
    func translateSpanishToChinese(_ text: String) async throws -> String
}

/// Uses MyMemory public API (no key, rate-limited). Replace with your provider in production if needed.
struct MyMemoryTranslationService: TranslationService {
    func translateSpanishToChinese(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "langpair", value: "es|zh-CN"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct Response: Decodable {
            struct Inner: Decodable {
                let translatedText: String
            }
            let responseData: Inner?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let raw = decoded.responseData?.translatedText ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct StubTranslationService: TranslationService {
    func translateSpanishToChinese(_ text: String) async throws -> String {
        "(离线)"
    }
}
