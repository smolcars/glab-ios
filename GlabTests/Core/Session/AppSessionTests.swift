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
            ),
            accountIndexStore: try makeIndexStore(
                for: storedSession
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
            accountIndexStore: try makeIndexStore(
                for: storedSession
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
            accountIndexStore: try makeIndexStore(
                for: storedSession
            ),
            currentDate: { now }
        )

        await appSession.restore()
        let persisted = try await store.load(
            for: GitLabAccountID(session: storedSession)
        )

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
            accountIndexStore: try makeIndexStore(
                for: storedSession
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
        let persisted = try await store.load(
            for: GitLabAccountID(session: storedSession)
        )

        #expect(persisted == storedSession)
        #expect(appSession.state == .signedIn(storedSession))
    }

    @Test("Deletes credentials before signing out")
    func signsOut() async throws {
        let storedSession = try makeSession(token: "delete-secret")
        let store = InMemoryGitLabCredentialStore(session: storedSession)
        let draftStore =
            InMemoryGitLabDiscussionDraftStore()
        let draftKey = draftKey(
            for: storedSession
        )
        let editDraftStore =
            InMemoryGitLabResourceEditDraftStore()
        let editDraftKey = editDraftKey(
            for: storedSession
        )
        let editDraft = makeEditDraft()
        try await draftStore.store(
            GitLabDiscussionDraft(
                body: "Unfinished comment",
                revision: 1
            ),
            for: draftKey
        )
        try await editDraftStore.store(
            editDraft,
            for: editDraftKey
        )
        let cache = InMemoryGitLabResponseCache()
        let cacheKey = try makeCacheKey(for: storedSession)
        try await cache.store(
            makeCachedResponse(),
            for: cacheKey
        )
        let appSession = AppSession(
            credentialStore: store,
            accountIndexStore: try makeIndexStore(
                for: storedSession
            ),
            responseCache: cache,
            discussionDraftStore:
                draftStore,
            resourceEditDraftStore:
                editDraftStore
        )
        await appSession.restore()

        try await appSession.signOut()
        let persisted = try await store.load(
            for: GitLabAccountID(session: storedSession)
        )

        #expect(persisted == nil)
        #expect(appSession.state == .signedOut)
        #expect(appSession.storedSession == nil)
        #expect(appSession.authenticationNotice == nil)
        #expect(await cache.response(for: cacheKey) == nil)
        #expect(
            await draftStore.draft(
                for: draftKey
            ) == nil
        )
        #expect(
            await editDraftStore.draft(
                for: editDraftKey
            ) == nil
        )
    }

    @Test("A rejected API session clears stored and in-memory user data")
    func handlesRejectedAPIAuthentication() async throws {
        let storedSession = try makeSession(token: "revoked-secret")
        let store = InMemoryGitLabCredentialStore(session: storedSession)
        let draftStore =
            InMemoryGitLabDiscussionDraftStore()
        let draftKey = draftKey(
            for: storedSession
        )
        let editDraftStore =
            InMemoryGitLabResourceEditDraftStore()
        let editDraftKey = editDraftKey(
            for: storedSession
        )
        let editDraft = makeEditDraft()
        let draft = GitLabDiscussionDraft(
            body: "Recover after signing in again",
            revision: 1
        )
        try await draftStore.store(
            draft,
            for: draftKey
        )
        try await editDraftStore.store(
            editDraft,
            for: editDraftKey
        )
        let cache = InMemoryGitLabResponseCache()
        let cacheKey = try makeCacheKey(for: storedSession)
        try await cache.store(
            makeCachedResponse(),
            for: cacheKey
        )
        let appSession = AppSession(
            credentialStore: store,
            accountIndexStore: try makeIndexStore(
                for: storedSession
            ),
            responseCache: cache,
            discussionDraftStore:
                draftStore,
            resourceEditDraftStore:
                editDraftStore
        )
        await appSession.restore()

        await appSession.handleAuthenticationFailure(
            .api(.unauthenticated),
            for: GitLabAccountID(
                session: storedSession
            )
        )
        let persisted = try await store.load(
            for: GitLabAccountID(session: storedSession)
        )

        #expect(persisted == nil)
        #expect(appSession.state == .signedOut)
        #expect(appSession.storedSession == nil)
        #expect(appSession.authenticationNotice == .expiredOrRevoked)
        #expect(await cache.response(for: cacheKey) == nil)
        #expect(
            await draftStore.draft(
                for: draftKey
            ) == draft
        )
        #expect(
            await editDraftStore.draft(
                for: editDraftKey
            ) == editDraft
        )
    }

    @Test("A recoverable API failure keeps the current session")
    func ignoresRecoverableAPIFailure() async throws {
        let storedSession = try makeSession(token: "offline-secret")
        let store = InMemoryGitLabCredentialStore(session: storedSession)
        let appSession = AppSession(
            credentialStore: store,
            accountIndexStore: try makeIndexStore(
                for: storedSession
            )
        )
        await appSession.restore()

        await appSession.handleAuthenticationFailure(
            .api(.connectivity(.notConnectedToInternet)),
            for: GitLabAccountID(
                session: storedSession
            )
        )

        #expect(appSession.state == .signedIn(storedSession))
        #expect(
            try await store.load(
                for: GitLabAccountID(session: storedSession)
            ) == storedSession
        )
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
            ),
            accountIndexStore: try makeIndexStore(
                for: original
            )
        )
        await appSession.restore()

        appSession.synchronizeRefreshedSession(
            refreshed,
            for: GitLabAccountID(session: original)
        )

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
        let appSession = AppSession(
            credentialStore: store,
            accountIndexStore: try makeIndexStore(
                for: original
            )
        )
        await appSession.restore()
        try await appSession.signOut()

        appSession.synchronizeRefreshedSession(
            refreshed,
            for: GitLabAccountID(session: original)
        )

        #expect(appSession.state == .signedOut)
        #expect(
            try await store.load(
                for: GitLabAccountID(session: original)
            ) == nil
        )
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
    func handlesRestoreFailure() async throws {
        let error = GitLabCredentialStoreError.corruptData
        let storedSession = try makeSession(token: "unreadable-secret")
        let appSession = AppSession(
            credentialStore: FailingCredentialStore(error: error),
            accountIndexStore: try makeIndexStore(
                for: storedSession
            )
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
            accountIndexStore: try makeIndexStore(
                for: storedSession
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

    nonisolated func draftKey(
        for session: GitLabStoredSession
    ) -> GitLabDiscussionDraftKey {
        GitLabDiscussionDraftKey(
            accountID:
                GitLabAccountID(
                    session: session
                ),
            resource: .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )
        )
    }

    nonisolated func editDraftKey(
        for session: GitLabStoredSession
    ) -> GitLabResourceEditDraftKey {
        GitLabResourceEditDraftKey(
            accountID:
                GitLabAccountID(
                    session: session
                ),
            target: .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )
        )
    }

    nonisolated func makeEditDraft()
        -> GitLabResourceEditDraft
    {
        GitLabResourceEditDraft(
            baseline:
                GitLabResourceEditSnapshot(
                    target: .issue(
                        GitLabIssueRoute(
                            projectID: 42,
                            issueIID: 7
                        )
                    ),
                    title: "Baseline",
                    description: "Original",
                    updatedAt: .distantPast
                ),
            title: "Edited",
            description: "Changed",
            revision: 1
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

        func load(
            for accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
            throw error
        }

        func save(
            _ session: GitLabStoredSession
        ) async throws(GitLabCredentialStoreError) {
            throw error
        }

        func delete(
            _ accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) {
            throw error
        }
    }

    nonisolated struct DeleteFailingCredentialStore: GitLabCredentialStore {
        let session: GitLabStoredSession
        let error: GitLabCredentialStoreError

        func load(
            for accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
            accountID == GitLabAccountID(session: session)
                ? session
                : nil
        }

        func save(
            _ session: GitLabStoredSession
        ) async throws(GitLabCredentialStoreError) {}

        func delete(
            _ accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) {
            throw error
        }
    }

    func makeIndexStore(
        for session: GitLabStoredSession
    ) throws -> InMemoryGitLabAccountIndexStore {
        InMemoryGitLabAccountIndexStore(
            index: try GitLabAccountIndex(
                accounts: [
                    GitLabAccountSummary(
                        session: session
                    ),
                ],
                activeAccountID: GitLabAccountID(
                    session: session
                )
            )
        )
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
