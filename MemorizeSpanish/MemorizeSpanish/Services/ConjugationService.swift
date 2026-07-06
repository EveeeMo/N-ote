import Foundation

enum SpanishTense: String, CaseIterable, Identifiable {
    case present = "现在时"
    case imperfect = "过去未完成"
    case preterite = "简单过去"
    case future = "简单将来"
    case conditional = "条件式"
    /// 虚拟式现在时（presente de subjuntivo）
    case presentSubjunctive = "虚拟现在时"
    /// 肯定命令式（与六格人称对应：— / tú / usted / nosotros / vosotros / ustedes）
    case imperativeAffirmative = "肯定命令式"

    var id: String { rawValue }

    /// 设置里展示顺序
    static var settingsOrder: [SpanishTense] {
        [.present, .imperativeAffirmative, .presentSubjunctive, .imperfect, .preterite, .future, .conditional]
    }
}

/// Six persons labels (Spanish)
private let spanishPersonLabels = ["yo", "tú", "él/ella", "nosotros", "vosotros", "ellos"]

struct ConjugationService {
    private let irregular: IrregularTable

    init() {
        self.irregular = IrregularTable.load()
    }

    func conjugationTable(infinitive: String, tense: SpanishTense) -> [String] {
        let inf = infinitive.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard inf.hasSuffix("ar") || inf.hasSuffix("er") || inf.hasSuffix("ir") else {
            return Array(repeating: "—", count: 6)
        }

        if irregular.hasIrregular(infinitive: inf, tense: tense) {
            return irregular.forms(infinitive: inf, tense: tense)
        }

        /// 原形已在不规则表中但该时态尚未录入 JSON 时，不能用规则动词推导（否则会给出错误形式）。
        if irregular.isListedVerb(infinitive: inf) {
            return Array(repeating: "—", count: 6)
        }

        return regularForms(infinitive: inf, tense: tense)
    }

    private func regularForms(infinitive: String, tense: SpanishTense) -> [String] {
        let stem = String(infinitive.dropLast(2))
        let ending = String(infinitive.suffix(2))

        switch tense {
        case .present:
            return presentRegular(stem: stem, ending: ending)
        case .imperfect:
            return imperfectRegular(stem: stem, ending: ending)
        case .preterite:
            return preteriteRegular(stem: stem, ending: ending)
        case .future:
            return futureConditionalRegular(infinitive: infinitive, isFuture: true)
        case .conditional:
            return futureConditionalRegular(infinitive: infinitive, isFuture: false)
        case .presentSubjunctive:
            return presentSubjunctiveRegular(infinitive: infinitive)
        case .imperativeAffirmative:
            return imperativeAffirmativeRegular(infinitive: infinitive)
        }
    }

    private func presentSubjunctiveRegular(infinitive: String) -> [String] {
        let stem = String(infinitive.dropLast(2))
        let ending = String(infinitive.suffix(2))
        switch ending {
        case "ar":
            return ["\(stem)e", "\(stem)es", "\(stem)e", "\(stem)emos", "\(stem)éis", "\(stem)en"]
        case "er", "ir":
            return ["\(stem)a", "\(stem)as", "\(stem)a", "\(stem)amos", "\(stem)áis", "\(stem)an"]
        default:
            return Array(repeating: "—", count: 6)
        }
    }

    /// 肯定命令式六格：yo 无常用形式；tú / usted(él位) / nosotros / vosotros / ustedes(ellos位)
    private func imperativeAffirmativeRegular(infinitive: String) -> [String] {
        let stem = String(infinitive.dropLast(2))
        let ending = String(infinitive.suffix(2))
        let subj = presentSubjunctiveRegular(infinitive: infinitive)
        guard subj.count == 6 else { return Array(repeating: "—", count: 6) }
        let túForm: String
        let vosForm: String
        switch ending {
        case "ar":
            túForm = stem + "a"
            vosForm = stem + "ad"
        case "er":
            túForm = stem + "e"
            vosForm = stem + "ed"
        case "ir":
            túForm = stem + "e"
            vosForm = stem + "id"
        default:
            return Array(repeating: "—", count: 6)
        }
        return ["—", túForm, subj[2], subj[3], vosForm, subj[5]]
    }

    private func presentRegular(stem: String, ending: String) -> [String] {
        switch ending {
        case "ar":
            return ["\(stem)o", "\(stem)as", "\(stem)a", "\(stem)amos", "\(stem)áis", "\(stem)an"]
        case "er":
            return ["\(stem)o", "\(stem)es", "\(stem)e", "\(stem)emos", "\(stem)éis", "\(stem)en"]
        case "ir":
            return ["\(stem)o", "\(stem)es", "\(stem)e", "\(stem)imos", "\(stem)ís", "\(stem)en"]
        default:
            return Array(repeating: "—", count: 6)
        }
    }

    private func imperfectRegular(stem: String, ending: String) -> [String] {
        switch ending {
        case "ar":
            return ["\(stem)aba", "\(stem)abas", "\(stem)aba", "\(stem)ábamos", "\(stem)abais", "\(stem)aban"]
        case "er", "ir":
            return ["\(stem)ía", "\(stem)ías", "\(stem)ía", "\(stem)íamos", "\(stem)íais", "\(stem)ían"]
        default:
            return Array(repeating: "—", count: 6)
        }
    }

    private func preteriteRegular(stem: String, ending: String) -> [String] {
        switch ending {
        case "ar":
            return ["\(stem)é", "\(stem)aste", "\(stem)ó", "\(stem)amos", "\(stem)asteis", "\(stem)aron"]
        case "er", "ir":
            return ["\(stem)í", "\(stem)iste", "\(stem)ió", "\(stem)imos", "\(stem)isteis", "\(stem)ieron"]
        default:
            return Array(repeating: "—", count: 6)
        }
    }

    private func futureConditionalRegular(infinitive: String, isFuture: Bool) -> [String] {
        let suffixes = isFuture ? ["é", "ás", "á", "emos", "éis", "án"] : ["ía", "ías", "ía", "íamos", "íais", "ían"]
        return suffixes.map { infinitive + $0 }
    }

    static var personLabels: [String] { spanishPersonLabels }
}

// MARK: - 全 App 展示的时态偏好（默认：现在时、肯定命令式、虚拟现在时）

enum ConjugationPreferences {
    static let storageKey = "app.conjugation.enabledTensesJSON"

    private static let defaultTenseRawValues: Set<String> = [
        SpanishTense.present.rawValue,
        SpanishTense.imperativeAffirmative.rawValue,
        SpanishTense.presentSubjunctive.rawValue,
    ]

    /// - 未写入或空字符串：视为未设置，返回默认三种时态。
    /// - `"[]"`：用户显式关闭全部，返回空数组。
    static func enabledTenses(fromJSONString storage: String?) -> [SpanishTense] {
        guard let s = storage else { return defaultOrdered() }
        if s.isEmpty { return defaultOrdered() }
        guard let data = s.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return defaultOrdered()
        }
        if decoded.isEmpty { return [] }
        let set = Set(decoded)
        return SpanishTense.settingsOrder.filter { set.contains($0.rawValue) }
    }

    static func enabledTenses() -> [SpanishTense] {
        enabledTenses(fromJSONString: UserDefaults.standard.string(forKey: storageKey))
    }

    private static func defaultOrdered() -> [SpanishTense] {
        SpanishTense.settingsOrder.filter { defaultTenseRawValues.contains($0.rawValue) }
    }
}

// MARK: - Irregular table (JSON)

private struct IrregularTable {
    private var stems: [String: IrregularVerbJSON]

    static func load() -> IrregularTable {
        guard let url = Bundle.main.url(forResource: "irregular_verbs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: IrregularVerbJSON].self, from: data)
        else {
            return IrregularTable(stems: [:])
        }
        return IrregularTable(stems: decoded)
    }

    func hasIrregular(infinitive: String, tense: SpanishTense) -> Bool {
        stems[infinitive]?.tenses[tense.rawValue] != nil
    }

    func isListedVerb(infinitive: String) -> Bool {
        stems[infinitive] != nil
    }

    func forms(infinitive: String, tense: SpanishTense) -> [String] {
        guard let verb = stems[infinitive],
              let arr = verb.tenses[tense.rawValue],
              arr.count == 6
        else {
            return Array(repeating: "—", count: 6)
        }
        return arr
    }
}

private struct IrregularVerbJSON: Codable {
    var tenses: [String: [String]]
}
