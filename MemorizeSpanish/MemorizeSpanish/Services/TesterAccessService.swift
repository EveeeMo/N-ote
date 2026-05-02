import Foundation

/// 内测邀请码：发码前在 `TestInviteCodes` 中登记，**重新打包**后分发给测试者；用于识别渠道，**不能**防破解。
enum TestInviteCodes {
    /// 在此添加可激活的邀请码（大小写需一致，建议大写+数字+连字符）。
    static let validCodes: Set<String> = [
        "NOTE-2026-INT-01",
    ]
}

@MainActor
final class TesterAccessService: ObservableObject {
    static let shared = TesterAccessService()

    private static let codeKey = "app.tester.inviteCode.activated"
    @Published private(set) var activatedCode: String?

    private init() { activatedCode = UserDefaults.standard.string(forKey: Self.codeKey) }

    var isActivated: Bool { activatedCode != nil }

    /// 与 `TestInviteCodes.validCodes` 逐字匹配即视为通过。
    func tryActivate(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, TestInviteCodes.validCodes.contains(trimmed) else { return false }
        UserDefaults.standard.set(trimmed, forKey: Self.codeKey)
        activatedCode = trimmed
        return true
    }

    func clearActivation() {
        UserDefaults.standard.removeObject(forKey: Self.codeKey)
        activatedCode = nil
    }
}
