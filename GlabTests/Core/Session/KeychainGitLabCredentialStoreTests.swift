import Foundation
import Security
import Testing
@testable import Glab

@Suite("Keychain GitLab credential store")
struct KeychainGitLabCredentialStoreTests {
    @Test("Saves, replaces, restores, and deletes a session")
    func persistsSingleSession() async throws {
        try await withStore { store in
            let first = try makeSession(username: "first", token: "first-secret")
            let replacement = try makeSession(
                username: "replacement",
                token: "replacement-secret"
            )

            let initial = try await store.load()
            #expect(initial == nil)

            try await store.save(first)
            let restoredFirst = try await store.load()
            #expect(restoredFirst == first)
            #expect(
                keychainAccessibility(
                    service: store.service,
                    account: store.account
                ) == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
            )

            try await store.save(replacement)
            let restoredReplacement = try await store.load()
            #expect(restoredReplacement == replacement)
            #expect(
                keychainAccessibility(
                    service: store.service,
                    account: store.account
                ) == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
            )

            try await store.delete()
            let deleted = try await store.load()
            #expect(deleted == nil)

            try await store.delete()
        }
    }

    @Test("Maps corrupt Keychain data without exposing it")
    func rejectsCorruptData() async throws {
        let secret = "corrupt-secret-that-must-not-escape"

        try await withStore { store in
            let status = insertRawData(
                Data(secret.utf8),
                service: store.service,
                account: store.account
            )
            #expect(status == errSecSuccess)

            do {
                _ = try await store.load()
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
            #expect(try await store.load() == replacement)
        }
    }

    @Test("Redacts its description")
    func redactsDescription() {
        let store = KeychainGitLabCredentialStore(
            service: "com.glab.tests.description",
            account: "current-session"
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
            service: "com.glab.tests.\(UUID().uuidString)",
            account: "current-session"
        )

        do {
            try await store.delete()
            try await operation(store)
            try await store.delete()
        } catch {
            try? await store.delete()
            throw error
        }
    }

    nonisolated func makeSession(
        username: String,
        token: String
    ) throws -> GitLabStoredSession {
        try GitLabStoredSession(
            host: GitLabHost("gitlab.example.com"),
            user: GitLabUserSummary(
                id: 42,
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
