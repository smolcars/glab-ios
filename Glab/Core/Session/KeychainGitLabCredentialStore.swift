import Foundation
import Security

actor KeychainGitLabCredentialStore:
    GitLabCredentialStore,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    nonisolated let service: String
    nonisolated let account: String

    init(
        service: String = "com.glab.ios.session",
        account: String = "current-session"
    ) {
        self.service = service
        self.account = account
    }

    nonisolated var description: String {
        "KeychainGitLabCredentialStore(session: <redacted>)"
    }

    nonisolated var debugDescription: String {
        description
    }

    func load() async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
        try loadSession()
    }

    func save(
        _ session: GitLabStoredSession
    ) async throws(GitLabCredentialStoreError) {
        try saveSession(session)
    }

    func replace(
        _ session: GitLabStoredSession,
        ifCurrentSessionIs expectedSession: GitLabStoredSession
    ) async throws(GitLabCredentialStoreError) -> Bool {
        guard try loadSession() == expectedSession else {
            return false
        }

        try saveSession(session)
        return true
    }

    func delete() async throws(GitLabCredentialStoreError) {
        try deleteSession()
    }

    private func loadSession() throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw .corruptData
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            do {
                return try decoder.decode(GitLabStoredSession.self, from: data)
            } catch {
                throw .corruptData
            }
        case errSecItemNotFound:
            return nil
        default:
            throw .keychain(status: status)
        }
    }

    private func saveSession(
        _ session: GitLabStoredSession
    ) throws(GitLabCredentialStoreError) {
        let data: Data

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(session)
        } catch {
            throw .encoding
        }

        var addQuery = baseQuery
        addQuery[kSecAttrAccessible as String] =
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addQuery[kSecValueData as String] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecDuplicateItem else {
            guard addStatus == errSecSuccess else {
                throw .keychain(status: addStatus)
            }
            return
        }

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [
                kSecAttrAccessible as String:
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecValueData as String: data,
            ] as CFDictionary
        )

        guard updateStatus == errSecSuccess else {
            throw .keychain(status: updateStatus)
        }
    }

    private func deleteSession() throws(GitLabCredentialStoreError) {
        let status = SecItemDelete(baseQuery as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw .keychain(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any,
        ]
    }
}
