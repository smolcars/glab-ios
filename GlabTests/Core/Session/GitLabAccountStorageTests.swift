import Foundation
import Testing
@testable import Glab

@Suite("GitLab account storage")
struct GitLabAccountStorageTests {
    @Test("Account identity uses canonical host and numeric user ID")
    func identifiesAccountsByHostAndUserID() throws {
        let first = try makeSession(
            host: "https://gitlab.example.com/",
            userID: 42,
            username: "shared-name",
            token: "first-secret"
        )
        let equivalent = try makeSession(
            host: "gitlab.example.com/api/v4",
            userID: 42,
            username: "renamed-user",
            token: "replacement-secret"
        )
        let otherHost = try makeSession(
            host: "gitlab.other.example.com",
            userID: 42,
            username: "shared-name",
            token: "other-secret"
        )

        #expect(GitLabAccountID(session: first) == GitLabAccountID(session: equivalent))
        #expect(GitLabAccountID(session: first) != GitLabAccountID(session: otherHost))
        #expect(
            String(describing: GitLabAccountID(session: first))
                == "GitLabAccountID(<redacted>)"
        )
    }

    @Test("Versioned account index round-trips without credentials")
    func persistsAccountIndex() throws {
        let suiteName = "com.glab.tests.accounts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storageKey = "account-index"
        let store = UserDefaultsGitLabAccountIndexStore(
            defaults: defaults,
            storageKey: storageKey
        )
        let first = try makeSession(
            host: "gitlab.example.com",
            userID: 42,
            username: "octocat",
            token: "never-store-first-secret"
        )
        let second = try makeSession(
            host: "gitlab.other.example.com",
            userID: 7,
            username: "gitlab-user",
            token: "never-store-second-secret"
        )
        let index = try GitLabAccountIndex(
            accounts: [
                GitLabAccountSummary(session: first),
                GitLabAccountSummary(session: second),
            ],
            activeAccountID: GitLabAccountID(session: second)
        )

        try store.save(index)

        #expect(try store.load() == index)
        let storedData = try #require(
            defaults.data(forKey: storageKey)
        )
        let storedText = String(decoding: storedData, as: UTF8.self)
        #expect(!storedText.contains("never-store-first-secret"))
        #expect(!storedText.contains("never-store-second-secret"))
    }

    @Test("Account index rejects duplicates and a missing active account")
    func validatesAccountIndex() throws {
        let session = try makeSession(
            host: "gitlab.example.com",
            userID: 42,
            username: "octocat",
            token: "secret"
        )
        let summary = GitLabAccountSummary(session: session)
        let missingID = GitLabAccountID(
            host: try GitLabHost("gitlab.other.example.com"),
            userID: 7
        )

        #expect(throws: GitLabAccountIndexError.duplicateAccount) {
            try GitLabAccountIndex(
                accounts: [summary, summary],
                activeAccountID: summary.id
            )
        }
        #expect(throws: GitLabAccountIndexError.missingActiveAccount) {
            try GitLabAccountIndex(
                accounts: [summary],
                activeAccountID: missingID
            )
        }
    }

    @Test("Corrupt account-index data is not treated as signed out")
    func rejectsCorruptAccountIndex() throws {
        let suiteName = "com.glab.tests.accounts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storageKey = "account-index"
        defaults.set(
            Data("not-an-account-index".utf8),
            forKey: storageKey
        )
        let store = UserDefaultsGitLabAccountIndexStore(
            defaults: defaults,
            storageKey: storageKey
        )

        #expect(throws: GitLabCredentialStoreError.corruptData) {
            try store.load()
        }
    }

    @Test("Credential storage isolates accounts and removes only its target")
    func isolatesStoredCredentials() async throws {
        let first = try makeSession(
            host: "gitlab.example.com",
            userID: 42,
            username: "shared-name",
            token: "first-secret"
        )
        let second = try makeSession(
            host: "gitlab.other.example.com",
            userID: 42,
            username: "shared-name",
            token: "second-secret"
        )
        let firstID = GitLabAccountID(session: first)
        let secondID = GitLabAccountID(session: second)
        let staleFirst = try makeSession(
            host: "gitlab.example.com",
            userID: 42,
            username: "shared-name",
            token: "stale-first-secret"
        )
        let store = InMemoryGitLabCredentialStore()

        try await store.save(first)
        try await store.save(second)

        #expect(try await store.load(for: firstID) == first)
        #expect(try await store.load(for: secondID) == second)

        let rejected = try await store.delete(
            firstID,
            ifCurrentSessionIs: staleFirst
        )
        let accepted = try await store.delete(
            firstID,
            ifCurrentSessionIs: first
        )

        #expect(!rejected)
        #expect(accepted)
        #expect(try await store.load(for: firstID) == nil)
        #expect(try await store.load(for: secondID) == second)
    }

    @Test("OAuth replacement cannot overwrite a different account")
    func isolatesConditionalReplacement() async throws {
        let first = try makeOAuthSession(
            host: "gitlab.example.com",
            userID: 42,
            accessToken: "first-access",
            refreshToken: "first-refresh"
        )
        let firstReplacement = try makeOAuthSession(
            host: "gitlab.example.com",
            userID: 42,
            accessToken: "rotated-access",
            refreshToken: "rotated-refresh"
        )
        let second = try makeOAuthSession(
            host: "gitlab.other.example.com",
            userID: 42,
            accessToken: "second-access",
            refreshToken: "second-refresh"
        )
        let store = InMemoryGitLabCredentialStore()
        try await store.save(first)
        try await store.save(second)

        let rejected = try await store.replace(
            firstReplacement,
            ifCurrentSessionIs: second
        )
        let accepted = try await store.replace(
            firstReplacement,
            ifCurrentSessionIs: first
        )

        #expect(!rejected)
        #expect(accepted)
        #expect(
            try await store.load(
                for: GitLabAccountID(session: first)
            ) == firstReplacement
        )
        #expect(
            try await store.load(
                for: GitLabAccountID(session: second)
            ) == second
        )
    }
}

private extension GitLabAccountStorageTests {
    nonisolated func makeSession(
        host: String,
        userID: Int,
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
            personalAccessTokenMetadata:
                GitLabPersonalAccessTokenMetadata(
                    scopes: ["read_api"],
                    expiresOn: nil
                ),
            credential:
                GitLabCredential.personalAccessToken(
                    token
                )
        )
    }

    nonisolated func makeOAuthSession(
        host: String,
        userID: Int,
        accessToken: String,
        refreshToken: String
    ) throws -> GitLabStoredSession {
        try GitLabStoredSession(
            host: GitLabHost(host),
            user: GitLabUserSummary(
                id: userID,
                username: "octocat",
                name: "The Octocat",
                avatarURL: nil
            ),
            oauthApplicationID: "application-id",
            personalAccessTokenMetadata: nil,
            credential: GitLabCredential.oauth(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: .distantPast
            )
        )
    }
}
