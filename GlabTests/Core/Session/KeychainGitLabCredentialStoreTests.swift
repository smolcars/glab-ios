import Foundation
import Security
import Testing
@testable import Glab

@Suite("Keychain GitLab credential store")
struct KeychainGitLabCredentialStoreTests {
    @Test("Saves, replaces, restores, and deletes independent sessions")
    func persistsMultipleSessions() async throws {
        try await withStore { store in
            let first = try makeSession(username: "first", token: "first-secret")
            let firstID = GitLabAccountID(session: first)
            let second = try makeSession(
                host: "gitlab.other.example.com",
                userID: 7,
                username: "second",
                token: "second-secret"
            )
            let secondID = GitLabAccountID(session: second)
            let replacement = try makeSession(
                username: "replacement",
                token: "replacement-secret"
            )

            let initial = try await store.load(
                for: firstID
            )
            #expect(initial == nil)

            try await store.save(first)
            try await store.save(second)
            let restoredFirst = try await store.load(
                for: firstID
            )
            #expect(restoredFirst == first)
            #expect(
                try await store.load(
                    for: secondID
                ) == second
            )
            #expect(
                keychainAccessibility(
                    service: store.service,
                    account: store.accountName(
                        for: firstID
                    )
                ) == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
            )
            #expect(
                !store.accountName(for: firstID)
                    .contains("gitlab.example.com")
            )

            try await store.save(replacement)
            let restoredReplacement = try await store.load(
                for: firstID
            )
            #expect(restoredReplacement == replacement)
            #expect(
                keychainAccessibility(
                    service: store.service,
                    account: store.accountName(
                        for: firstID
                    )
                ) == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
            )

            try await store.delete(firstID)
            let deleted = try await store.load(
                for: firstID
            )
            #expect(deleted == nil)
            #expect(
                try await store.load(
                    for: secondID
                ) == second
            )

            try await store.delete(firstID)
        }
    }

    @Test("Maps corrupt Keychain data without exposing it")
    func rejectsCorruptData() async throws {
        let secret = "corrupt-secret-that-must-not-escape"

        try await withStore { store in
            let accountID = GitLabAccountID(
                host: try GitLabHost(
                    "gitlab.example.com"
                ),
                userID: 42
            )
            let status = insertRawData(
                Data(secret.utf8),
                service: store.service,
                account: store.accountName(
                    for: accountID
                )
            )
            #expect(status == errSecSuccess)

            do {
                _ = try await store.load(
                    for: accountID
                )
                Issue.record("Expected corrupt Keychain data to fail")
            } catch {
                let storeError = try #require(
                    error as? GitLabCredentialStoreError
                )
                #expect(storeError == .corruptData)
                #expect(!String(describing: error).contains(secret))
                #expect(!String(reflecting: error).contains(secret))
            }
        }
    }

    @Test("Conditionally replaces only the expected Keychain session")
    func conditionallyReplacesSession() async throws {
        try await withStore { store in
            let original = try makeSession(
                username: "original",
                token: "original-secret"
            )
            let stale = try makeSession(
                username: "stale",
                token: "stale-secret"
            )
            let replacement = try makeSession(
                username: "replacement",
                token: "replacement-secret"
            )
            try await store.save(original)

            let rejected = try await store.replace(
                replacement,
                ifCurrentSessionIs: stale
            )
            let accepted = try await store.replace(
                replacement,
                ifCurrentSessionIs: original
            )

            #expect(!rejected)
            #expect(accepted)
            #expect(
                try await store.load(
                    for: GitLabAccountID(
                        session: original
                    )
                ) == replacement
            )
        }
    }

    @Test("Redacts its description")
    func redactsDescription() {
        let store = KeychainGitLabCredentialStore(
            service: "com.glab.tests.description"
        )

        #expect(String(describing: store).contains("<redacted>"))
        #expect(String(reflecting: store).contains("<redacted>"))
    }
}

private extension KeychainGitLabCredentialStoreTests {
    func withStore(
        operation: (KeychainGitLabCredentialStore) async throws -> Void
    ) async throws {
        let store = KeychainGitLabCredentialStore(
            service: "com.glab.tests.\(UUID().uuidString)"
        )

        do {
            try await store.deleteAll()
            try await operation(store)
            try await store.deleteAll()
        } catch {
            try? await store.deleteAll()
            throw error
        }
    }

    nonisolated func makeSession(
        host: String = "gitlab.example.com",
        userID: Int = 42,
        username: String,
        token: String
    ) throws -> GitLabStoredSession {
        try GitLabStoredSession(
            host: GitLabHost(host),
            user: GitLabUserSummary(
                id: userID,
                username: username,
                name: username.capitalized,
                avatarURL: nil
            ),
            oauthApplicationID: nil,
            personalAccessTokenMetadata: GitLabPersonalAccessTokenMetadata(
                scopes: ["api"],
                expiresOn: nil
            ),
            credential: GitLabCredential.personalAccessToken(token)
        )
    }

    nonisolated func insertRawData(
        _ data: Data,
        service: String,
        account: String
    ) -> OSStatus {
        SecItemAdd(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessible as String:
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
                kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any,
                kSecValueData as String: data,
            ] as CFDictionary,
            nil
        )
    }

    nonisolated func keychainAccessibility(
        service: String,
        account: String
    ) -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
                kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any,
                kSecReturnAttributes as String: kCFBooleanTrue as Any,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ] as CFDictionary,
            &result
        )

        guard
            status == errSecSuccess,
            let attributes = result as? [String: Any]
        else {
            return nil
        }

        return attributes[kSecAttrAccessible as String] as? String
    }
}
