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

    private var memoryFallback: [CredentialAccount: String] = [:]
    private let lock = NSLock()

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
            lock.lock()
            memoryFallback.removeValue(forKey: account)
            lock.unlock()
            return true
        }
        if updateStatus != errSecItemNotFound && updateStatus != errSecParam && updateStatus != errSecNotAvailable {
            return false
        }

        var insert = query
        insert.merge(attributes) { current, _ in current }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        if addStatus == errSecSuccess {
            lock.lock()
            memoryFallback.removeValue(forKey: account)
            lock.unlock()
            return true
        }

        // When Keychain is inaccessible (headless shell, CI, unit tests without GUI session),
        // gracefully fall back to process-level memory storage.
        if addStatus == errSecNotAvailable || addStatus == errSecParam || addStatus == -34018 {
            lock.lock()
            memoryFallback[account] = trimmed
            lock.unlock()
            return true
        }

        return false
    }

    public func readSecret(for account: CredentialAccount) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let copyStatus = SecItemCopyMatching(query as CFDictionary, &item)
        if copyStatus == errSecSuccess,
           let data = item as? Data,
           let secret = String(data: data, encoding: .utf8),
           !secret.isEmpty {
            return secret
        }

        lock.lock()
        defer { lock.unlock() }
        return memoryFallback[account]
    }

    @discardableResult
    public func deleteSecret(for account: CredentialAccount) -> Bool {
        _ = SecItemDelete(baseQuery(for: account) as CFDictionary)
        lock.lock()
        memoryFallback.removeValue(forKey: account)
        lock.unlock()
        return true
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
