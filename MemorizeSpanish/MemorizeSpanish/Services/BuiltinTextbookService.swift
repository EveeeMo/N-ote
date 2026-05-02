import Foundation

struct BuiltinBookMeta: Codable, Identifiable, Hashable {
    var bookId: String
    var title: String
    var subtitle: String?
    /// Resource name without `.json`, under `BuiltinBooks/`
    var bundleFileName: String
    var id: String { bookId }
}

private struct BuiltinBookCatalogFile: Codable {
    var books: [BuiltinBookMeta]
}

enum BuiltinTextbookService {
    static func loadCatalog() throws -> [BuiltinBookMeta] {
        let data = try loadResourceData("catalog", subdirectory: "BuiltinBooks")
        return try JSONDecoder().decode(BuiltinBookCatalogFile.self, from: data).books
    }

    /// DELE A1–B2 等计划用词表目录（`dele_catalog.json`）。
    static func loadDELECatalog() throws -> [BuiltinBookMeta] {
        let data = try loadResourceData("dele_catalog", subdirectory: "BuiltinBooks")
        return try JSONDecoder().decode(BuiltinBookCatalogFile.self, from: data).books
    }

    static func loadUnits(bundleFileName: String) throws -> [BundledUnitDTO] {
        let data = try loadResourceData(bundleFileName, subdirectory: "BuiltinBooks")
        return try JSONDecoder().decode([BundledUnitDTO].self, from: data)
    }

    private static func loadResourceData(_ name: String, subdirectory: String) throws -> Data {
        if DELEPackStorage.isDELEPack(name), name != "dele_catalog" {
            return try DELEPackStorage.loadPackData(bundleFileName: name)
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: "json")
        else {
            throw ImportError.missingFile
        }
        return try Data(contentsOf: url)
    }
}
