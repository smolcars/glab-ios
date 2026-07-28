import Foundation
import Testing
@testable import Glab

@Suite("In-memory GitLab credential store")
struct InMemoryGitLabCredentialStoreTests {
    @Test("Starts without a stored session")
    func startsEmpty() async throws {
        let store = InMemoryGitLabCredentialStore()
        let accountID = GitLabAccountID(
            host: try GitLabHost("gitlab.example.com"),
            userID: 42
        )

        let session = try await load(
            from: store,
            accountID: accountID
        )

        #expect(session == nil)
    }

    @Test("Saves and restores a session")
    func savesAndRestores() async throws {
        let store = InMemoryGitLabCredentialStore()
        let expected = try makeSession(username: "octocat", token: "first-secret")

        try await store.save(expected)
        let restored = try await load(
            from: store,
            accountID: GitLabAccountID(
                session: expected
            )
        )

        #expect(restored == expected)
    }

    @Test("Replaces the single stored session")
    func replacesSession() async throws {
        let first = try makeSession(username: "first", token: "first-secret")
        let replacement = try makeSession(
            username: "replacement",
            token: "replacement-secret"
        )
        let store = InMemoryGitLabCredentialStore(session: first)

        try await store.save(replacement)
        let restored = try await store.load(
            for: GitLabAccountID(session: first)
        )

        #expect(restored == replacement)
    }

    @Test("Conditionally replaces only the expected session")
    func conditionallyReplacesSession() async throws {
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
        let store = InMemoryGitLabCredentialStore(session: original)

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
                for: GitLabAccountID(session: original)
            ) == replacement
        )
    }

    @Test("Deletes the stored session")
    func deletesSession() async throws {
        let store = InMemoryGitLabCredentialStore(
            session: try makeSession(username: "octocat", token: "pat-secret")
        )
        let accountID = GitLabAccountID(
            host: try GitLabHost("gitlab.example.com"),
            userID: 42
        )

        try await store.delete(accountID)
        let restored = try await store.load(
            for: accountID
        )

        #expect(restored == nil)
    }

    @Test("Does not expose the stored session in descriptions")
    func redactsDescription() async throws {
        let secret = "never-print-store-secret"
        let store = InMemoryGitLabCredentialStore(
            session: try makeSession(username: "octocat", token: secret)
        )

        #expect(!String(describing: store).contains(secret))
        #expect(!String(reflecting: store).contains(secret))
    }
}

private extension InMemoryGitLabCredentialStoreTests {
    nonisolated func load(
        from store: any GitLabCredentialStore,
        accountID: GitLabAccountID
    ) async throws -> GitLabStoredSession? {
        try await store.load(for: accountID)
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
}
