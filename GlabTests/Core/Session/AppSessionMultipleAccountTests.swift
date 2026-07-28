import Foundation
import Testing
@testable import Glab

@Suite("App session multiple accounts")
@MainActor
struct AppSessionMultipleAccountTests {
    @Test("Restores the indexed active account")
    func restoresActiveAccount() async throws {
        let first = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "first"
        )
        let second = try makeSession(
            host: "gitlab.com",
            userID: 2,
            username: "second"
        )
        let indexStore = try makeIndexStore(
            sessions: [first, second],
            active: second
        )
        let appSession = AppSession(
            credentialStore: InMemoryGitLabCredentialStore(
                sessions: [first, second]
            ),
            accountIndexStore: indexStore
        )

        await appSession.restore()

        #expect(appSession.state == .signedIn(second))
        #expect(
            appSession.activeAccountID
                == GitLabAccountID(session: second)
        )
    }

    @Test("Adding a second account preserves the first and makes the new account active")
    func addsSecondAccount() async throws {
        let first = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "first"
        )
        let second = try makeSession(
            host: "gitlab.com",
            userID: 2,
            username: "second"
        )
        let credentialStore = InMemoryGitLabCredentialStore(
            session: first
        )
        let indexStore = try makeIndexStore(
            sessions: [first],
            active: first
        )
        let appSession = AppSession(
            credentialStore: credentialStore,
            accountIndexStore: indexStore
        )
        await appSession.restore()

        try await appSession.establish(second)

        #expect(appSession.state == .signedIn(second))
        #expect(
            appSession.accounts.map(\.id)
                == [
                    GitLabAccountID(session: first),
                    GitLabAccountID(session: second),
                ]
        )
        #expect(
            try await credentialStore.load(
                for: GitLabAccountID(session: first)
            ) == first
        )
        #expect(
            try await credentialStore.load(
                for: GitLabAccountID(session: second)
            ) == second
        )
        #expect(
            try indexStore.load().activeAccountID
                == GitLabAccountID(session: second)
        )
    }

    @Test("Switching accounts persists across a new app session")
    func persistsAccountSwitch() async throws {
        let first = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "first"
        )
        let second = try makeSession(
            host: "gitlab.com",
            userID: 2,
            username: "second"
        )
        let credentialStore = InMemoryGitLabCredentialStore(
            sessions: [first, second]
        )
        let indexStore = try makeIndexStore(
            sessions: [first, second],
            active: first
        )
        let appSession = AppSession(
            credentialStore: credentialStore,
            accountIndexStore: indexStore
        )
        await appSession.restore()

        try await appSession.switchAccount(
            to: GitLabAccountID(session: second)
        )

        let restoredAppSession = AppSession(
            credentialStore: credentialStore,
            accountIndexStore: indexStore
        )
        await restoredAppSession.restore()
        #expect(
            restoredAppSession.state
                == .signedIn(second)
        )
    }

    @Test("Removing an inactive account preserves the active account and its cache")
    func removesInactiveAccount() async throws {
        let first = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "first"
        )
        let second = try makeSession(
            host: "gitlab.com",
            userID: 2,
            username: "second"
        )
        let credentialStore = InMemoryGitLabCredentialStore(
            sessions: [first, second]
        )
        let indexStore = try makeIndexStore(
            sessions: [first, second],
            active: first
        )
        let cache = InMemoryGitLabResponseCache()
        let firstKey = try makeCacheKey(for: first)
        let secondKey = try makeCacheKey(for: second)
        await cache.store(
            makeCachedResponse(body: "first"),
            for: firstKey
        )
        await cache.store(
            makeCachedResponse(body: "second"),
            for: secondKey
        )
        let appSession = AppSession(
            credentialStore: credentialStore,
            accountIndexStore: indexStore,
            responseCache: cache
        )
        await appSession.restore()

        try await appSession.removeAccount(
            GitLabAccountID(session: second)
        )

        #expect(appSession.state == .signedIn(first))
        #expect(
            try await credentialStore.load(
                for: GitLabAccountID(session: first)
            ) == first
        )
        #expect(
            try await credentialStore.load(
                for: GitLabAccountID(session: second)
            ) == nil
        )
        #expect(await cache.response(for: firstKey) != nil)
        #expect(await cache.response(for: secondKey) == nil)
    }

    @Test("Removing the active account activates the next account")
    func removesActiveAccount() async throws {
        let first = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "first"
        )
        let second = try makeSession(
            host: "gitlab.com",
            userID: 2,
            username: "second"
        )
        let appSession = AppSession(
            credentialStore: InMemoryGitLabCredentialStore(
                sessions: [first, second]
            ),
            accountIndexStore: try makeIndexStore(
                sessions: [first, second],
                active: first
            )
        )
        await appSession.restore()

        try await appSession.removeAccount(
            GitLabAccountID(session: first)
        )

        #expect(appSession.state == .signedIn(second))
        #expect(
            appSession.accounts.map(\.id)
                == [GitLabAccountID(session: second)]
        )
    }

    @Test("A missing active credential falls through to the next account")
    func skipsMissingActiveCredential() async throws {
        let missing = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "missing"
        )
        let available = try makeSession(
            host: "gitlab.com",
            userID: 2,
            username: "available"
        )
        let indexStore = try makeIndexStore(
            sessions: [missing, available],
            active: missing
        )
        let appSession = AppSession(
            credentialStore: InMemoryGitLabCredentialStore(
                session: available
            ),
            accountIndexStore: indexStore
        )

        await appSession.restore()

        #expect(appSession.state == .signedIn(available))
        #expect(
            try indexStore.load().accounts.map(\.id)
                == [GitLabAccountID(session: available)]
        )
    }

    @Test("The most recently requested account switch wins")
    func latestSwitchWins() async throws {
        let first = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "first"
        )
        let second = try makeSession(
            host: "gitlab.com",
            userID: 2,
            username: "second"
        )
        let third = try makeSession(
            host: "gitlab.example.net",
            userID: 3,
            username: "third"
        )
        let secondID = GitLabAccountID(session: second)
        let thirdID = GitLabAccountID(session: third)
        let credentialStore = GatedCredentialStore(
            sessions: [first, second, third],
            gatedAccountIDs: [secondID, thirdID]
        )
        let appSession = AppSession(
            credentialStore: credentialStore,
            accountIndexStore: try makeIndexStore(
                sessions: [first, second, third],
                active: first
            )
        )
        await appSession.restore()

        let earlierSwitch = Task {
            try await appSession.switchAccount(to: secondID)
        }
        await credentialStore.waitUntilRequested(secondID)
        let latestSwitch = Task {
            try await appSession.switchAccount(to: thirdID)
        }
        await credentialStore.waitUntilRequested(thirdID)

        await credentialStore.finishLoading(thirdID)
        try await latestSwitch.value
        await credentialStore.finishLoading(secondID)
        try await earlierSwitch.value

        #expect(appSession.state == .signedIn(third))
    }

    @Test("A switch during removal cannot restore the removed account")
    func switchDuringRemovalPreservesRemoval() async throws {
        let first = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "first"
        )
        let removed = try makeSession(
            host: "gitlab.com",
            userID: 2,
            username: "removed"
        )
        let selected = try makeSession(
            host: "gitlab.example.net",
            userID: 3,
            username: "selected"
        )
        let removedID = GitLabAccountID(session: removed)
        let selectedID = GitLabAccountID(session: selected)
        let credentialStore = GatedDeletionCredentialStore(
            sessions: [first, removed, selected],
            gatedAccountID: removedID
        )
        let indexStore = try makeIndexStore(
            sessions: [first, removed, selected],
            active: first
        )
        let appSession = AppSession(
            credentialStore: credentialStore,
            accountIndexStore: indexStore
        )
        await appSession.restore()

        let removal = Task {
            try await appSession.removeAccount(removedID)
        }
        await credentialStore.waitUntilDeleteRequested()

        try await appSession.switchAccount(to: selectedID)
        await credentialStore.finishDeletion()
        try await removal.value

        #expect(appSession.state == .signedIn(selected))
        #expect(
            !appSession.accounts.contains {
                $0.id == removedID
            }
        )
        #expect(
            !(try indexStore.load()).accounts.contains {
                $0.id == removedID
            }
        )
        #expect(
            try await credentialStore.load(
                for: removedID
            ) == nil
        )
    }

    @Test("Stale authentication callbacks cannot affect the active account")
    func ignoresStaleAuthenticationCallbacks() async throws {
        let first = try makeOAuthSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "first",
            accessToken: "first-access"
        )
        let second = try makeOAuthSession(
            host: "gitlab.com",
            userID: 2,
            username: "second",
            accessToken: "second-access"
        )
        let credentialStore = InMemoryGitLabCredentialStore(
            sessions: [first, second]
        )
        let appSession = AppSession(
            credentialStore: credentialStore,
            accountIndexStore: try makeIndexStore(
                sessions: [first, second],
                active: second
            )
        )
        await appSession.restore()

        await appSession.handleAuthenticationFailure(
            .api(.unauthenticated),
            for: GitLabAccountID(session: first)
        )
        appSession.synchronizeRefreshedSession(
            try makeOAuthSession(
                host: "gitlab.example.com",
                userID: 1,
                username: "first",
                accessToken: "late-access"
            ),
            for: GitLabAccountID(session: first)
        )

        #expect(appSession.state == .signedIn(second))
        #expect(
            try await credentialStore.load(
                for: GitLabAccountID(session: first)
            ) == first
        )
    }

    @Test("Terminal authentication failure removes only its owning account")
    func removesRejectedActiveAccountOnly() async throws {
        let first = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "first"
        )
        let second = try makeSession(
            host: "gitlab.com",
            userID: 2,
            username: "second"
        )
        let credentialStore = InMemoryGitLabCredentialStore(
            sessions: [first, second]
        )
        let appSession = AppSession(
            credentialStore: credentialStore,
            accountIndexStore: try makeIndexStore(
                sessions: [first, second],
                active: second
            )
        )
        await appSession.restore()

        await appSession.handleAuthenticationFailure(
            .api(.unauthenticated),
            for: GitLabAccountID(session: second)
        )

        #expect(appSession.state == .signedIn(first))
        #expect(
            try await credentialStore.load(
                for: GitLabAccountID(session: first)
            ) == first
        )
        #expect(
            try await credentialStore.load(
                for: GitLabAccountID(session: second)
            ) == nil
        )
    }
}

private extension AppSessionMultipleAccountTests {
    actor GatedCredentialStore: GitLabCredentialStore {
        private let sessions:
            [GitLabAccountID: GitLabStoredSession]
        private let gatedAccountIDs: Set<GitLabAccountID>
        private var requestedAccountIDs:
            Set<GitLabAccountID> = []
        private var requestWaiters:
            [GitLabAccountID: [CheckedContinuation<Void, Never>]] = [:]
        private var loadContinuations:
            [GitLabAccountID: CheckedContinuation<Void, Never>] = [:]

        init(
            sessions: [GitLabStoredSession],
            gatedAccountIDs: Set<GitLabAccountID>
        ) {
            self.sessions = Dictionary(
                uniqueKeysWithValues: sessions.map {
                    (GitLabAccountID(session: $0), $0)
                }
            )
            self.gatedAccountIDs = gatedAccountIDs
        }

        func load(
            for accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
            requestedAccountIDs.insert(accountID)
            requestWaiters.removeValue(forKey: accountID)?
                .forEach { $0.resume() }

            if gatedAccountIDs.contains(accountID) {
                await withCheckedContinuation { continuation in
                    loadContinuations[accountID] = continuation
                }
            }

            return sessions[accountID]
        }

        func save(
            _ session: GitLabStoredSession
        ) async throws(GitLabCredentialStoreError) {}

        func delete(
            _ accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) {}

        func waitUntilRequested(
            _ accountID: GitLabAccountID
        ) async {
            guard !requestedAccountIDs.contains(accountID) else {
                return
            }

            await withCheckedContinuation { continuation in
                requestWaiters[accountID, default: []]
                    .append(continuation)
            }
        }

        func finishLoading(
            _ accountID: GitLabAccountID
        ) {
            loadContinuations.removeValue(
                forKey: accountID
            )?
            .resume()
        }
    }

    actor GatedDeletionCredentialStore:
        GitLabCredentialStore
    {
        private var sessions:
            [GitLabAccountID: GitLabStoredSession]
        private let gatedAccountID: GitLabAccountID
        private var deleteWasRequested = false
        private var deleteRequestWaiter:
            CheckedContinuation<Void, Never>?
        private var deletionContinuation:
            CheckedContinuation<Void, Never>?

        init(
            sessions: [GitLabStoredSession],
            gatedAccountID: GitLabAccountID
        ) {
            self.sessions = Dictionary(
                uniqueKeysWithValues: sessions.map {
                    (GitLabAccountID(session: $0), $0)
                }
            )
            self.gatedAccountID = gatedAccountID
        }

        func load(
            for accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
            sessions[accountID]
        }

        func save(
            _ session: GitLabStoredSession
        ) async throws(GitLabCredentialStoreError) {
            sessions[GitLabAccountID(session: session)] =
                session
        }

        func delete(
            _ accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) {
            if accountID == gatedAccountID {
                deleteWasRequested = true
                deleteRequestWaiter?.resume()
                deleteRequestWaiter = nil
                await withCheckedContinuation {
                    deletionContinuation = $0
                }
            }
            sessions[accountID] = nil
        }

        func waitUntilDeleteRequested() async {
            guard !deleteWasRequested else {
                return
            }
            await withCheckedContinuation {
                deleteRequestWaiter = $0
            }
        }

        func finishDeletion() {
            deletionContinuation?.resume()
            deletionContinuation = nil
        }
    }

    func makeIndexStore(
        sessions: [GitLabStoredSession],
        active: GitLabStoredSession
    ) throws -> InMemoryGitLabAccountIndexStore {
        InMemoryGitLabAccountIndexStore(
            index: try GitLabAccountIndex(
                accounts: sessions.map(
                    GitLabAccountSummary.init
                ),
                activeAccountID: GitLabAccountID(
                    session: active
                )
            )
        )
    }

    nonisolated func makeSession(
        host: String,
        userID: Int,
        username: String
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
                    scopes: ["api"],
                    expiresOn: nil
                ),
            credential: .personalAccessToken(
                "\(username)-secret"
            )
        )
    }

    nonisolated func makeOAuthSession(
        host: String,
        userID: Int,
        username: String,
        accessToken: String
    ) throws -> GitLabStoredSession {
        try GitLabStoredSession(
            host: GitLabHost(host),
            user: GitLabUserSummary(
                id: userID,
                username: username,
                name: username.capitalized,
                avatarURL: nil
            ),
            oauthApplicationID: "application-id",
            personalAccessTokenMetadata: nil,
            credential: .oauth(
                accessToken: accessToken,
                refreshToken: "refresh-token",
                expiresAt: .distantFuture
            )
        )
    }

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

    nonisolated func makeCachedResponse(
        body: String
    ) -> GitLabCachedResponse {
        GitLabCachedResponse(
            body: Data(body.utf8),
            nextPageURL: nil,
            totalCount: nil,
            entityTag: nil,
            lastModified: nil,
            storedAt: .distantPast,
            lastAccessedAt: .distantPast
        )
    }
}
