import AuthenticationServices
import Foundation

/// Sign in with Apple：用于稳定身份与后续可扩展的云端同步；不自动分割本地 SwiftData（数据仍在沙盒、随设备）。
@MainActor
final class AppleAccountManager: ObservableObject {
    static let shared = AppleAccountManager()

    private static let keychainUserIdKey = "apple.userIdentifier"
    private static let defaultsEmailKey = "app.account.appleEmail"
    private static let defaultsNameKey = "app.account.fullName"

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var userIdentifier: String?
    @Published private(set) var emailSnapshot: String?
    @Published private(set) var fullNameSnapshot: String?
    @Published private(set) var credentialStateDescription: String?

    private let appleProvider = ASAuthorizationAppleIDProvider()

    private init() {
        let id = KeychainStore.string(account: Self.keychainUserIdKey)
        userIdentifier = id
        isSignedIn = id != nil
        emailSnapshot = UserDefaults.standard.string(forKey: Self.defaultsEmailKey)
        fullNameSnapshot = UserDefaults.standard.string(forKey: Self.defaultsNameKey)
    }

    /// 将 Sign in with Apple 回调里拿到的凭证写入本机并更新发布属性。
    func completeSignIn(with credential: ASAuthorizationAppleIDCredential) {
        let id = credential.user
        KeychainStore.set(id, account: Self.keychainUserIdKey)
        userIdentifier = id
        isSignedIn = true
        if let em = credential.email, !em.isEmpty {
            UserDefaults.standard.set(em, forKey: Self.defaultsEmailKey)
            emailSnapshot = em
        }
        if let name = credential.fullName {
            let s = [name.givenName, name.familyName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !s.isEmpty {
                UserDefaults.standard.set(s, forKey: Self.defaultsNameKey)
                fullNameSnapshot = s
            }
        }
        credentialStateDescription = nil
    }

    /// 只清除本机保存的 Apple 登录态；不会删除 SwiftData 词库。
    func signOut() {
        KeychainStore.delete(account: Self.keychainUserIdKey)
        UserDefaults.standard.removeObject(forKey: Self.defaultsEmailKey)
        UserDefaults.standard.removeObject(forKey: Self.defaultsNameKey)
        userIdentifier = nil
        isSignedIn = false
        emailSnapshot = nil
        fullNameSnapshot = nil
        credentialStateDescription = nil
    }

    /// 用于导出备份、客服排查的匿名前缀（非完整 id）。
    var userIdentifierPrefixForDiagnostics: String? {
        userIdentifier.map { String($0.prefix(8)) + "…" }
    }

    func refreshCredentialStateIfNeeded() {
        guard let id = userIdentifier else { return }
        appleProvider.getCredentialState(forUserID: id) { [weak self] state, _ in
            Task { @MainActor in
                self?.applyCredentialState(state)
            }
        }
    }

    private func applyCredentialState(_ state: ASAuthorizationAppleIDProvider.CredentialState) {
        switch state {
        case .authorized:
            credentialStateDescription = nil
        case .revoked, .notFound:
            signOut()
            credentialStateDescription = "Apple 端已撤销或未找到登录，请重新登录。"
        case .transferred:
            signOut()
            credentialStateDescription = "账号已转移，请重新登录。"
        @unknown default:
            break
        }
    }
}
