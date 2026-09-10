import Foundation
import Security

public enum CredentialAccount: String, CaseIterable, Sendable {
    case jira = "jira"
    case github = "github"

    public var displayName: String {
        switch self {
        case .jira: return "Jira"
        case .github: return "GitHub"
        }
    }
}

/// Stores API tokens in the macOS Keychain.
///
/// Only secrets live here. Non-secret companion fields (Jira base URL and email,
/// GitHub username) are kept in `PersistedAppState` so they can be inspected and
/// edited without a Keychain prompt.
public final class CredentialStore: @unchecked Sendable {
    public static let shared = CredentialStore()

    private let service: String

    public init(service: String = "com.miniops.credentials") {
        self.service = service
    }

    private func baseQuery(for account: CredentialAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
    }

    @discardableResult
    public func saveSecret(_ secret: String, for account: CredentialAccount) -> Bool {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return deleteSecret(for: account)
        }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let query = baseQuery(for: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }

        var insert = query
        insert.merge(attributes) { current, _ in current }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    public func readSecret(for account: CredentialAccount) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8),
              !secret.isEmpty else {
            return nil
        }
        return secret
    }

    @discardableResult
    public func deleteSecret(for account: CredentialAccount) -> Bool {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public func hasSecret(for account: CredentialAccount) -> Bool {
        readSecret(for: account) != nil
    }

    /// Never returns the secret itself - only enough to confirm which token is stored.
    public func maskedSecret(for account: CredentialAccount) -> String? {
        guard let secret = readSecret(for: account) else { return nil }
        let suffix = secret.suffix(4)
        return suffix.count == 4 ? "••••••••\(suffix)" : "••••••••"
    }
}
