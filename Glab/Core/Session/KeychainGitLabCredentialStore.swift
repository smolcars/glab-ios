import Foundation
import Security

nonisolated struct KeychainGitLabCredentialStore:
    GitLabCredentialStore,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let service: String
    let account: String

    init(
        service: String = "com.glab.ios.session",
        account: String = "current-session"
    ) {
        self.service = service
        self.account = account
    }

    var description: String {
        "KeychainGitLabCredentialStore(session: <redacted>)"
    }

    var debugDescription: String {
        description
    }

    @concurrent
    func load() async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
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

    @concurrent
    func save(
        _ session: GitLabStoredSession
    ) async throws(GitLabCredentialStoreError) {
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
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
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
                    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecValueData as String: data,
            ] as CFDictionary
        )

        guard updateStatus == errSecSuccess else {
            throw .keychain(status: updateStatus)
        }
    }

    @concurrent
    func delete() async throws(GitLabCredentialStoreError) {
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
