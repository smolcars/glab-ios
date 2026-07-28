import Foundation
import Testing
@testable import Glab

@Suite("App session")
struct AppSessionTests {
    @Test("Restores a signed-out state when no credentials exist")
    func restoresSignedOutState() async {
        let appSession = AppSession(
            credentialStore: InMemoryGitLabCredentialStore()
        )

        #expect(appSession.state == .restoring)

        await appSession.restore()

        #expect(appSession.state == .signedOut)
    }

    @Test("Restores a signed-in session")
    func restoresSignedInState() async throws {
        let storedSession = try makeSession(token: "stored-secret")
        let appSession = AppSession(
            credentialStore: InMemoryGitLabCredentialStore(
                session: storedSession
            )
        )

        await appSession.restore()

        #expect(appSession.state == .signedIn(storedSession))
        #expect(appSession.storedSession == storedSession)
    }

    @Test("Restores an expired OAuth session that can refresh")
    func restoresRefreshableOAuthSession() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let storedSession = try makeOAuthSession(
            refreshToken: "refresh-secret",
            expiresAt: now.addingTimeInterval(-60)
        )
        let appSession = AppSession(
            credentialStore: InMemoryGitLabCredentialStore(
                session: storedSession
            ),
            currentDate: { now }
        )

        await appSession.restore()

        #expect(appSession.state == .signedIn(storedSession))
        #expect(appSession.authenticationNotice == nil)
    }

    @Test("Removes an expired OAuth session that cannot refresh")
    func removesInvalidOAuthSession() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let storedSession = try makeOAuthSession(
            refreshToken: nil,
            expiresAt: now.addingTimeInterval(-60)
        )
        let store = InMemoryGitLabCredentialStore(session: storedSession)
        let appSession = AppSession(
            credentialStore: store,
            currentDate: { now }
        )

        await appSession.restore()
        let persisted = try await store.load()

        #expect(persisted == nil)
        #expect(appSession.state == .signedOut)
        #expect(appSession.storedSession == nil)
        #expect(appSession.authenticationNotice == .expiredOrRevoked)
    }

    @Test("Purges an invalid OAuth cache when credential deletion fails")
    func purgesInvalidOAuthCacheAfterDeletionFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let error = GitLabCredentialStoreError.keychain(
            status: -1
        )
        let storedSession = try makeOAuthSession(
            refreshToken: nil,
            expiresAt: now.addingTimeInterval(-60)
        )
        let cache = InMemoryGitLabResponseCache()
        let cacheKey = try makeCacheKey(for: storedSession)
        try await cache.store(
            makeCachedResponse(),
            for: cacheKey
        )
        let appSession = AppSession(
            credentialStore: DeleteFailingCredentialStore(
                session: storedSession,
                error: error
            ),
            responseCache: cache,
            currentDate: { now }
        )

        await appSession.restore()

        #expect(appSession.state == .failed(error))
        #expect(
            appSession.authenticationNotice
                == .expiredOrRevoked
        )
        #expect(await cache.response(for: cacheKey) == nil)
    }

    @Test("Persists a newly established session before signing in")
    func establishesSession() async throws {
        let store = InMemoryGitLabCredentialStore()
        let appSession = AppSession(credentialStore: store)
        let storedSession = try makeSession(token: "new-secret")

        try await appSession.establish(storedSession)
        let persisted = try await store.load()

        #expect(persisted == storedSession)
        #expect(appSession.state == .signedIn(storedSession))
    }

    @Test("Deletes credentials before signing out")
    func signsOut() async throws {
        let storedSession = try makeSession(token: "delete-secret")
        let store = InMemoryGitLabCredentialStore(session: storedSession)
        let cache = InMemoryGitLabResponseCache()
        let cacheKey = try makeCacheKey(for: storedSession)
        try await cache.store(
            makeCachedResponse(),
            for: cacheKey
        )
        let appSession = AppSession(
            credentialStore: store,
            responseCache: cache
        )
        await appSession.restore()

        try await appSession.signOut()
        let persisted = try await store.load()

        #expect(persisted == nil)
        #expect(appSession.state == .signedOut)
        #expect(appSession.storedSession == nil)
        #expect(appSession.authenticationNotice == nil)
        #expect(await cache.response(for: cacheKey) == nil)
    }

    @Test("A rejected API session clears stored and in-memory user data")
    func handlesRejectedAPIAuthentication() async throws {
        let storedSession = try makeSession(token: "revoked-secret")
        let store = InMemoryGitLabCredentialStore(session: storedSession)
        let cache = InMemoryGitLabResponseCache()
        let cacheKey = try makeCacheKey(for: storedSession)
        try await cache.store(
            makeCachedResponse(),
            for: cacheKey
        )
        let appSession = AppSession(
            credentialStore: store,
            responseCache: cache
        )
        await appSession.restore()

        await appSession.handleAuthenticationFailure(
            .api(.unauthenticated)
        )
        let persisted = try await store.load()

        #expect(persisted == nil)
        #expect(appSession.state == .signedOut)
        #expect(appSession.storedSession == nil)
        #expect(appSession.authenticationNotice == .expiredOrRevoked)
        #expect(await cache.response(for: cacheKey) == nil)
    }

    @Test("A recoverable API failure keeps the current session")
    func ignoresRecoverableAPIFailure() async throws {
        let storedSession = try makeSession(token: "offline-secret")
        let store = InMemoryGitLabCredentialStore(session: storedSession)
        let appSession = AppSession(credentialStore: store)
        await appSession.restore()

        await appSession.handleAuthenticationFailure(
            .api(.connectivity(.notConnectedToInternet))
        )

        #expect(appSession.state == .signedIn(storedSession))
        #expect(try await store.load() == storedSession)
        #expect(appSession.authenticationNotice == nil)
    }

    @Test("Synchronizes a rotated OAuth credential for the current account")
    func synchronizesRefreshedOAuthSession() async throws {
        let original = try makeOAuthSession(
            refreshToken: "original-refresh",
            expiresAt: .distantPast
        )
        let refreshed = try makeOAuthSession(
            refreshToken: "rotated-refresh",
            expiresAt: .distantFuture
        )
        let appSession = AppSession(
            credentialStore: InMemoryGitLabCredentialStore(
                session: original
            )
        )
        await appSession.restore()

        appSession.synchronizeRefreshedSession(refreshed)

        #expect(appSession.state == .signedIn(refreshed))
    }

    @Test("Ignores a late refresh after sign-out")
    func ignoresLateRefreshAfterSignOut() async throws {
        let original = try makeOAuthSession(
            refreshToken: "original-refresh",
            expiresAt: .distantPast
        )
        let refreshed = try makeOAuthSession(
            refreshToken: "rotated-refresh",
            expiresAt: .distantFuture
        )
        let store = InMemoryGitLabCredentialStore(session: original)
        let appSession = AppSession(credentialStore: store)
        await appSession.restore()
        try await appSession.signOut()

        appSession.synchronizeRefreshedSession(refreshed)

        #expect(appSession.state == .signedOut)
        #expect(try await store.load() == nil)
    }

    @Test("Classifies only expired or rejected credentials for reauthentication")
    func classifiesAuthenticationFailures() {
        #expect(
            GitLabSessionClientError.api(.unauthenticated)
                .requiresReauthentication
        )
        #expect(
            GitLabSessionClientError.refresh(.unavailable)
                .requiresReauthentication
        )
        #expect(
            GitLabSessionClientError.refresh(.token(.invalidGrant))
                .requiresReauthentication
        )
        #expect(
            !GitLabSessionClientError.api(
                .connectivity(.notConnectedToInternet)
            )
            .requiresReauthentication
        )
        #expect(
            !GitLabSessionClientError.refresh(
                .token(.connectivity(.timedOut))
            )
            .requiresReauthentication
        )
    }

    @Test("Surfaces restore failures")
    func handlesRestoreFailure() async {
        let error = GitLabCredentialStoreError.corruptData
        let appSession = AppSession(
            credentialStore: FailingCredentialStore(error: error)
        )

        await appSession.restore()

        #expect(appSession.state == .failed(error))
    }

    @Test("Remains signed in when credential deletion fails")
    func preservesSessionOnSignOutFailure() async throws {
        let storedSession = try makeSession(token: "still-stored-secret")
        let error = GitLabCredentialStoreError.keychain(status: -1)
        let cache = InMemoryGitLabResponseCache()
        let cacheKey = try makeCacheKey(for: storedSession)
        try await cache.store(
            makeCachedResponse(),
            for: cacheKey
        )
        let appSession = AppSession(
            credentialStore: DeleteFailingCredentialStore(
                session: storedSession,
                error: error
            ),
            responseCache: cache
        )
        await appSession.restore()

        await #expect(throws: error) {
            try await appSession.signOut()
        }

        #expect(appSession.state == .signedIn(storedSession))
        #expect(await cache.response(for: cacheKey) != nil)
    }

    @Test("Redacts credentials from state descriptions")
    func redactsStateDescription() throws {
        let secret = "never-print-session-state-secret"
        let state = AppSession.State.signedIn(
            try makeSession(token: secret)
        )

        #expect(!String(describing: state).contains(secret))
        #expect(!String(reflecting: state).contains(secret))
    }
}

private extension AppSessionTests {
    nonisolated func makeCacheKey(
        for session: GitLabStoredSession
    ) throws -> GitLabResponseCacheKey {
        GitLabResponseCacheKey(
            account: GitLabCacheAccount(session: session),
            requestURL: try #require(
                URL(
                    string:
                        "\(session.host.apiBaseURL.absoluteString)/projects"
                )
            )
        )
    }

    nonisolated func makeCachedResponse() -> GitLabCachedResponse {
        GitLabCachedResponse(
            body: Data("[]".utf8),
            nextPageURL: nil,
            totalCount: nil,
            entityTag: nil,
            lastModified: nil,
            storedAt: .distantPast,
            lastAccessedAt: .distantPast
        )
    }

    nonisolated struct FailingCredentialStore: GitLabCredentialStore {
        let error: GitLabCredentialStoreError

        func load() async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
            throw error
        }

        func save(
            _ session: GitLabStoredSession
        ) async throws(GitLabCredentialStoreError) {
            throw error
        }

        func delete() async throws(GitLabCredentialStoreError) {
            throw error
        }
    }

    nonisolated struct DeleteFailingCredentialStore: GitLabCredentialStore {
        let session: GitLabStoredSession
        let error: GitLabCredentialStoreError

        func load() async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
            session
        }

        func save(
            _ session: GitLabStoredSession
        ) async throws(GitLabCredentialStoreError) {}

        func delete() async throws(GitLabCredentialStoreError) {
            throw error
        }
    }

    nonisolated func makeSession(token: String) throws -> GitLabStoredSession {
        try GitLabStoredSession(
            host: GitLabHost("gitlab.example.com"),
            user: GitLabUserSummary(
                id: 42,
                username: "octocat",
                name: "The Octocat",
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

    nonisolated func makeOAuthSession(
        refreshToken: String?,
        expiresAt: Date
    ) throws -> GitLabStoredSession {
        try GitLabStoredSession(
            host: GitLabHost("gitlab.example.com"),
            user: GitLabUserSummary(
                id: 42,
                username: "octocat",
                name: "The Octocat",
                avatarURL: nil
            ),
            oauthApplicationID: "application-id",
            personalAccessTokenMetadata: nil,
            credential: GitLabCredential.oauth(
                accessToken: "oauth-secret",
                refreshToken: refreshToken,
                expiresAt: expiresAt
            )
        )
    }
}
