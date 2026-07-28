import CryptoKit
import Foundation
import Security

actor KeychainGitLabCredentialStore:
    GitLabCredentialStore,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    nonisolated let service: String

    init(
        service: String = "com.glab.ios.accounts"
    ) {
        self.service = service
    }

    nonisolated var description: String {
        "KeychainGitLabCredentialStore(session: <redacted>)"
    }

    nonisolated var debugDescription: String {
        description
    }

    func load(
        for accountID: GitLabAccountID
    ) async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
        try loadSession(for: accountID)
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
        let accountID = GitLabAccountID(
            session: expectedSession
        )
        guard
            GitLabAccountID(session: session) == accountID,
            try loadSession(for: accountID)
                == expectedSession
        else {
            return false
        }

        try saveSession(session)
        return true
    }

    func delete(
        _ accountID: GitLabAccountID
    ) async throws(GitLabCredentialStoreError) {
        try deleteSession(for: accountID)
    }

    func delete(
        _ accountID: GitLabAccountID,
        ifCurrentSessionIs expectedSession:
            GitLabStoredSession
    ) async throws(GitLabCredentialStoreError) -> Bool {
        guard
            GitLabAccountID(session: expectedSession)
                == accountID,
            try loadSession(for: accountID)
                == expectedSession
        else {
            return false
        }

        try deleteSession(for: accountID)
        return true
    }

    nonisolated func accountName(
        for accountID: GitLabAccountID
    ) -> String {
        let digest = SHA256.hash(
            data: Data(
                accountID.storageIdentifier.utf8
            )
        )
        .map {
            String(format: "%02x", $0)
        }
        .joined()
        return "account-\(digest)"
    }

    func deleteAll() throws(GitLabCredentialStoreError) {
        let status = SecItemDelete(
            serviceQuery as CFDictionary
        )
        guard
            status == errSecSuccess
                || status == errSecItemNotFound
        else {
            throw .keychain(status: status)
        }
    }

    private func loadSession(
        for accountID: GitLabAccountID
    ) throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
        var query = baseQuery(for: accountID)
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
                let session = try decoder.decode(
                    GitLabStoredSession.self,
                    from: data
                )
                guard
                    GitLabAccountID(session: session)
                        == accountID
                else {
                    throw GitLabCredentialStoreError
                        .corruptData
                }
                return session
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

        let accountID = GitLabAccountID(
            session: session
        )
        let baseQuery = baseQuery(for: accountID)
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

    private func deleteSession(
        for accountID: GitLabAccountID
    ) throws(GitLabCredentialStoreError) {
        let status = SecItemDelete(
            baseQuery(for: accountID) as CFDictionary
        )

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw .keychain(status: status)
        }
    }

    private func baseQuery(
        for accountID: GitLabAccountID
    ) -> [String: Any] {
        var query = serviceQuery
        query[kSecAttrAccount as String] =
            accountName(for: accountID)
        return query
    }

    private var serviceQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any,
        ]
    }
}
