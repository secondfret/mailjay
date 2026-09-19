import Foundation
import Security

struct KeychainStore {
    private let service = "com.personal.MailJay"
    private let secretsAccount = "app-secrets"
    private let legacyAccounts = [
        "google-client-id",
        "google-client-secret",
        "jev-api-key",
        "google-oauth-token"
    ]

    struct Secrets: Codable, Equatable, Sendable {
        var googleClientID: String = ""
        var googleClientSecret: String = ""
        var jevAPIKey: String = ""
        var accounts: [MailAccount] = []
        var activeAccountEmail: String?
        /// Legacy single-token field; migrated into `accounts` on load.
        var oauthTokenJSON: String?

        enum CodingKeys: String, CodingKey {
            case googleClientID, googleClientSecret, jevAPIKey
            case accounts, activeAccountEmail, oauthTokenJSON
        }

        init(
            googleClientID: String = "",
            googleClientSecret: String = "",
            jevAPIKey: String = "",
            accounts: [MailAccount] = [],
            activeAccountEmail: String? = nil,
            oauthTokenJSON: String? = nil
        ) {
            self.googleClientID = googleClientID
            self.googleClientSecret = googleClientSecret
            self.jevAPIKey = jevAPIKey
            self.accounts = accounts
            self.activeAccountEmail = activeAccountEmail
            self.oauthTokenJSON = oauthTokenJSON
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            googleClientID = try container.decodeIfPresent(String.self, forKey: .googleClientID) ?? ""
            googleClientSecret = try container.decodeIfPresent(String.self, forKey: .googleClientSecret) ?? ""
            jevAPIKey = try container.decodeIfPresent(String.self, forKey: .jevAPIKey) ?? ""
            accounts = try container.decodeIfPresent([MailAccount].self, forKey: .accounts) ?? []
            activeAccountEmail = try container.decodeIfPresent(String.self, forKey: .activeAccountEmail)
            oauthTokenJSON = try container.decodeIfPresent(String.self, forKey: .oauthTokenJSON)
        }
    }

    func loadSecrets() -> Secrets {
        var secrets = readCombinedSecrets() ?? migrateLegacySecrets()
        secrets = migrateLegacyTokenIfNeeded(secrets)
        return secrets
    }

    func saveSecrets(_ secrets: Secrets) throws {
        var normalized = secrets
        normalized.oauthTokenJSON = nil
        let data = try JSONEncoder().encode(normalized)
        let status = addItem(data: data, useDataProtection: true)
        if status == errSecSuccess { return }

        let fallback = addItem(data: data, useDataProtection: false)
        guard fallback == errSecSuccess else { throw KeychainError.status(fallback) }
    }

    func deleteSecrets() {
        deleteCombined(useDataProtection: true)
        deleteCombined(useDataProtection: false)
        legacyAccounts.forEach(deleteLegacy)
    }

    private func migrateLegacySecrets() -> Secrets {
        let migrated = Secrets(
            googleClientID: readLegacy("google-client-id") ?? "",
            googleClientSecret: readLegacy("google-client-secret") ?? "",
            jevAPIKey: readLegacy("jev-api-key") ?? "",
            oauthTokenJSON: readLegacy("google-oauth-token")
        )
        if migrated != Secrets() {
            try? saveSecrets(migrated)
            legacyAccounts.forEach(deleteLegacy)
        }
        return migrated
    }

    private func migrateLegacyTokenIfNeeded(_ secrets: Secrets) -> Secrets {
        guard secrets.accounts.isEmpty,
              let tokenJSON = secrets.oauthTokenJSON,
              let data = tokenJSON.data(using: .utf8),
              let token = try? JSONDecoder().decode(OAuthToken.self, from: data) else {
            return secrets
        }
        var updated = secrets
        let placeholder = MailAccount(email: "Primary Gmail", token: token)
        updated.accounts = [placeholder]
        updated.activeAccountEmail = placeholder.email
        updated.oauthTokenJSON = nil
        try? saveSecrets(updated)
        return updated
    }

    private func addItem(data: Data, useDataProtection: Bool) -> OSStatus {
        var query = baseQuery(account: secretsAccount)
        if useDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil)
    }

    private func readCombinedSecrets() -> Secrets? {
        if let secrets = readCombined(useDataProtection: true) {
            return secrets
        }
        return readCombined(useDataProtection: false)
    }

    private func readCombined(useDataProtection: Bool) -> Secrets? {
        var query = baseQuery(account: secretsAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if useDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Secrets.self, from: data)
    }

    private func deleteCombined(useDataProtection: Bool) {
        var query = baseQuery(account: secretsAccount)
        if useDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        SecItemDelete(query as CFDictionary)
    }

    private func readLegacy(_ account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteLegacy(_ account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    enum KeychainError: LocalizedError {
        case status(OSStatus)
        var errorDescription: String? {
            switch self {
            case .status(let status): "Keychain error \(status)."
            }
        }
    }
}
