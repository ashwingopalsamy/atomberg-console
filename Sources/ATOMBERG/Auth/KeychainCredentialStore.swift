import Foundation
import Security

enum KeychainError: Error, Sendable {
    case status(OSStatus)
    /// An earlier read failed and Refresh has not retried it. Thrown instead of reading again, which could prompt again.
    case unavailable
}

/// Reads the Keychain at most once per launch. Every read of an item the current build is not trusted for can
/// raise the system's password prompt, and the cloud client asks for the credentials and the access token on
/// every call, so an uncached store prompted again and again. Both live in one item, so there is one prompt,
/// not two. The cache is the only state, behind a lock, so instances are safe to share across tasks.
final class KeychainCredentialStore: CredentialStoring, @unchecked Sendable {
    private static let account = "credentials"
    /// Where the access token lived before it shared the credentials item. Only ever deleted.
    private static let legacyTokenAccount = "access-token"

    private struct Stored: Codable {
        var credentials: Credentials
        var accessToken: AccessToken?
    }

    private enum Cache {
        case unloaded
        /// nil means the Keychain has no item.
        case loaded(Stored?)
    }

    private let service: String
    private let lock = NSLock()
    private var cache = Cache.unloaded

    init(service: String = "com.ashwin.ATOMBERG") {
        self.service = service
    }

    func hasCredentials() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .loaded(let stored) = cache { return stored != nil }
        var query = itemQuery(account: Self.account)
        // Attributes only. The item's data stays sealed, so this never raises the access prompt.
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return true
    }

    func loadCredentials() throws -> Credentials? {
        try load()?.credentials
    }

    func saveCredentials(_ credentials: Credentials) throws {
        // New credentials invalidate the token that was issued for the old ones.
        try store(Stored(credentials: credentials, accessToken: nil))
    }

    func deleteCredentials() throws {
        lock.lock()
        defer { lock.unlock() }
        try remove(account: Self.account)
        try remove(account: Self.legacyTokenAccount)
        cache = .loaded(nil)
    }

    func loadAccessToken() throws -> AccessToken? {
        try load()?.accessToken
    }

    func saveAccessToken(_ token: AccessToken) throws {
        guard var stored = try load() else { throw KeychainError.status(errSecItemNotFound) }
        stored.accessToken = token
        try store(stored)
    }

    func deleteAccessToken() throws {
        guard var stored = try load(), stored.accessToken != nil else { return }
        stored.accessToken = nil
        try store(stored)
    }

    // MARK: - Cache

    private func load() throws -> Stored? {
        lock.lock()
        defer { lock.unlock() }
        if case .loaded(let stored) = cache { return stored }
        let stored = try readItem()
        cache = .loaded(stored)
        return stored
    }

    private func store(_ stored: Stored) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeItem(stored)
        cache = .loaded(stored)
    }

    // MARK: - Keychain

    private func itemQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    private func readItem() throws -> Stored? {
        var query = itemQuery(account: Self.account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data else { throw KeychainError.status(errSecDecode) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Stored.self, from: data)
        } catch {
            // The item an earlier version wrote holds the bare credentials. Its separate token item is not read:
            // that would prompt again, and a new token costs one call.
            guard let credentials = try? decoder.decode(Credentials.self, from: data) else { throw error }
            return Stored(credentials: credentials, accessToken: nil)
        }
    }

    private func writeItem(_ stored: Stored) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(stored)

        let query = itemQuery(account: Self.account) as CFDictionary
        // No kSecAttrAccessible: it does not govern prompts here. The login keychain trusts the code signature,
        // so a build signed with a stable identity (scripts/bundle.sh) is trusted once for good.
        let attributes: [CFString: Any] = [kSecValueData: data]

        var status = SecItemUpdate(query, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = itemQuery(account: Self.account)
            item.merge(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
            // Two concurrent first saves can both miss the update; the loser's add fails and must retry as an update.
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query, attributes as CFDictionary)
            }
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    private func remove(account: String) throws {
        let status = SecItemDelete(itemQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}
