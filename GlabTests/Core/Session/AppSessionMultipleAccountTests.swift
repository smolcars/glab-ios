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

    @Test("Removing an inactive account purges only its cache and edit drafts")
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
        let editDraftStore =
            InMemoryGitLabResourceEditDraftStore()
        let firstDraftKey =
            makeEditDraftKey(for: first)
        let secondDraftKey =
            makeEditDraftKey(for: second)
        let firstDraft =
            makeEditDraft(title: "First")
        let secondDraft =
            makeEditDraft(title: "Second")
        try await editDraftStore.store(
            firstDraft,
            for: firstDraftKey
        )
        try await editDraftStore.store(
            secondDraft,
            for: secondDraftKey
        )
        let traceStore =
            RecordingGitLabJobTraceStore()
        let appSession = AppSession(
            credentialStore: credentialStore,
            accountIndexStore: indexStore,
            responseCache: cache,
            jobTraceStore: traceStore,
            resourceEditDraftStore:
                editDraftStore
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
        #expect(
            await traceStore.removedAccountIDs
                == [
                    GitLabAccountID(
                        session: second
                    ),
                ]
        )
        #expect(
            await editDraftStore.draft(
                for: firstDraftKey
            ) == firstDraft
        )
        #expect(
            await editDraftStore.draft(
                for: secondDraftKey
            ) == nil
        )
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
        let traceStore =
            RecordingGitLabJobTraceStore()
        let appSession = AppSession(
            credentialStore: InMemoryGitLabCredentialStore(
                session: available
            ),
            accountIndexStore: indexStore,
            jobTraceStore: traceStore
        )

        await appSession.restore()

        #expect(appSession.state == .signedIn(available))
        #expect(
            try indexStore.load().accounts.map(\.id)
                == [GitLabAccountID(session: available)]
        )
        #expect(
            await traceStore.removedAccountIDs
                == [
                    GitLabAccountID(
                        session: missing
                    ),
                ]
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

    @Test("A stale removal cannot delete a re-established credential")
    func staleRemovalCannotDeleteReestablishedCredential() async throws {
        let original = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "same-user",
            token: "original-secret"
        )
        let replacement = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "same-user",
            token: "replacement-secret"
        )
        let accountID = GitLabAccountID(session: original)
        let credentialStore = GatedDeletionCredentialStore(
            sessions: [original],
            gatedAccountID: accountID
        )
        let appSession = AppSession(
            credentialStore: credentialStore,
            accountIndexStore: try makeIndexStore(
                sessions: [original],
                active: original
            )
        )
        await appSession.restore()

        let removal = Task {
            try await appSession.removeAccount(accountID)
        }
        await credentialStore.waitUntilDeleteRequested()

        try await appSession.establish(replacement)
        await credentialStore.finishDeletion()
        try await removal.value

        #expect(appSession.state == .signedIn(replacement))
        #expect(
            try await credentialStore.load(
                for: accountID
            ) == replacement
        )
    }

    @Test("A returning account cancels stale trace-cache deletion")
    func returningAccountCancelsStaleTracePurge()
        async throws
    {
        let original = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "same-user",
            token: "original-secret"
        )
        let replacement = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "same-user",
            token: "replacement-secret"
        )
        let accountID = GitLabAccountID(
            session: original
        )
        let responseCache =
            GatedAccountRemovalResponseCache()
        let traceStore =
            RecordingGitLabJobTraceStore()
        let appSession = AppSession(
            credentialStore:
                InMemoryGitLabCredentialStore(
                    session: original
                ),
            accountIndexStore: try makeIndexStore(
                sessions: [original],
                active: original
            ),
            responseCache: responseCache,
            jobTraceStore: traceStore
        )
        await appSession.restore()

        let removal = Task {
            try await appSession.removeAccount(
                accountID
            )
        }
        await responseCache.waitUntilRemovalStarts()
        try await appSession.establish(replacement)
        await responseCache.finishRemoval()
        try await removal.value

        #expect(
            appSession.state
                == .signedIn(replacement)
        )
        #expect(
            await traceStore.removedAccountIDs
                .isEmpty
        )
    }

    @Test("A stale add cannot delete the latest credential")
    func staleEstablishCannotDeleteLatestCredential() async throws {
        let stale = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "same-user",
            token: "stale-secret"
        )
        let latest = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "same-user",
            token: "latest-secret"
        )
        let accountID = GitLabAccountID(session: latest)
        let credentialStore =
            GatedFirstSaveCredentialStore()
        let appSession = AppSession(
            credentialStore: credentialStore
        )
        await appSession.restore()

        let staleEstablish = Task {
            try await appSession.establish(stale)
        }
        await credentialStore.waitUntilFirstSave()

        try await appSession.establish(latest)
        await credentialStore.finishFirstSave()
        try await staleEstablish.value

        #expect(appSession.state == .signedIn(latest))
        #expect(
            try await credentialStore.load(
                for: accountID
            ) == latest
        )
    }

    @Test("A failed fallback load leaves a failure state, not restoring")
    func failedFallbackLoadDoesNotLeaveRestoringState() async throws {
        let removed = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "removed"
        )
        let fallback = try makeSession(
            host: "gitlab.com",
            userID: 2,
            username: "fallback"
        )
        let failure =
            GitLabCredentialStoreError.keychain(
                status: -50
            )
        let credentialStore =
            FailingFallbackLoadCredentialStore(
                sessions: [removed, fallback],
                failingAccountID:
                    GitLabAccountID(session: fallback),
                error: failure
            )
        let appSession = AppSession(
            credentialStore: credentialStore,
            accountIndexStore: try makeIndexStore(
                sessions: [removed, fallback],
                active: removed
            )
        )
        await appSession.restore()
        await credentialStore.enableFailure()

        await #expect(throws: failure) {
            try await appSession.removeAccount(
                GitLabAccountID(session: removed)
            )
        }

        #expect(appSession.state == .failed(failure))
    }

    @Test("A stale deletion failure cannot override a newer sign-in")
    func staleDeletionFailureCannotOverrideNewerSignIn() async throws {
        let rejected = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "same-user",
            token: "rejected-secret"
        )
        let replacement = try makeSession(
            host: "gitlab.example.com",
            userID: 1,
            username: "same-user",
            token: "replacement-secret"
        )
        let accountID = GitLabAccountID(session: rejected)
        let credentialStore = GatedDeletionCredentialStore(
            sessions: [rejected],
            gatedAccountID: accountID,
            deletionError: .keychain(status: -50)
        )
        let appSession = AppSession(
            credentialStore: credentialStore,
            accountIndexStore: try makeIndexStore(
                sessions: [rejected],
                active: rejected
            )
        )
        await appSession.restore()

        let invalidation = Task {
            await appSession.handleAuthenticationFailure(
                .api(.unauthenticated),
                for: accountID
            )
        }
        await credentialStore.waitUntilDeleteRequested()

        try await appSession.establish(replacement)
        await credentialStore.finishDeletion()
        await invalidation.value

        #expect(appSession.state == .signedIn(replacement))
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
        #expect(
            appSession.authenticationNotice
                == .expiredOrRevoked
        )

        appSession.dismissAuthenticationNotice()

        #expect(appSession.authenticationNotice == nil)
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
        private let deletionError:
            GitLabCredentialStoreError?

        init(
            sessions: [GitLabStoredSession],
            gatedAccountID: GitLabAccountID,
            deletionError:
                GitLabCredentialStoreError? = nil
        ) {
            self.sessions = Dictionary(
                uniqueKeysWithValues: sessions.map {
                    (GitLabAccountID(session: $0), $0)
                }
            )
            self.gatedAccountID = gatedAccountID
            self.deletionError = deletionError
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
            if let deletionError {
                throw deletionError
            }
            sessions[accountID] = nil
        }

        func delete(
            _ accountID: GitLabAccountID,
            ifCurrentSessionIs expectedSession:
                GitLabStoredSession
        ) async throws(GitLabCredentialStoreError) -> Bool {
            if accountID == gatedAccountID {
                deleteWasRequested = true
                deleteRequestWaiter?.resume()
                deleteRequestWaiter = nil
                await withCheckedContinuation {
                    deletionContinuation = $0
                }
            }
            if let deletionError {
                throw deletionError
            }
            guard
                GitLabAccountID(session: expectedSession)
                    == accountID,
                sessions[accountID] == expectedSession
            else {
                return false
            }

            sessions[accountID] = nil
            return true
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

    actor GatedFirstSaveCredentialStore:
        GitLabCredentialStore
    {
        private var sessions:
            [GitLabAccountID: GitLabStoredSession] = [:]
        private var saveCount = 0
        private var firstSaveWasRequested = false
        private var firstSaveRequestWaiter:
            CheckedContinuation<Void, Never>?
        private var firstSaveContinuation:
            CheckedContinuation<Void, Never>?

        func load(
            for accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
            sessions[accountID]
        }

        func save(
            _ session: GitLabStoredSession
        ) async throws(GitLabCredentialStoreError) {
            saveCount += 1
            sessions[GitLabAccountID(session: session)] =
                session

            if saveCount == 1 {
                firstSaveWasRequested = true
                firstSaveRequestWaiter?.resume()
                firstSaveRequestWaiter = nil
                await withCheckedContinuation {
                    firstSaveContinuation = $0
                }
            }
        }

        func delete(
            _ accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) {
            sessions[accountID] = nil
        }

        func waitUntilFirstSave() async {
            guard !firstSaveWasRequested else {
                return
            }
            await withCheckedContinuation {
                firstSaveRequestWaiter = $0
            }
        }

        func finishFirstSave() {
            firstSaveContinuation?.resume()
            firstSaveContinuation = nil
        }
    }

    actor FailingFallbackLoadCredentialStore:
        GitLabCredentialStore
    {
        private var sessions:
            [GitLabAccountID: GitLabStoredSession]
        private let failingAccountID: GitLabAccountID
        private let error: GitLabCredentialStoreError
        private var isFailureEnabled = false

        init(
            sessions: [GitLabStoredSession],
            failingAccountID: GitLabAccountID,
            error: GitLabCredentialStoreError
        ) {
            self.sessions = Dictionary(
                uniqueKeysWithValues: sessions.map {
                    (GitLabAccountID(session: $0), $0)
                }
            )
            self.failingAccountID = failingAccountID
            self.error = error
        }

        func load(
            for accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
            if
                isFailureEnabled,
                accountID == failingAccountID
            {
                throw error
            }
            return sessions[accountID]
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
            sessions[accountID] = nil
        }

        func enableFailure() {
            isFailureEnabled = true
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
        username: String,
        token: String? = nil
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
                token ?? "\(username)-secret"
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

    nonisolated func makeEditDraftKey(
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

    nonisolated func makeEditDraft(
        title: String
    ) -> GitLabResourceEditDraft {
        GitLabResourceEditDraft(
            baseline:
                GitLabResourceEditSnapshot(
                    target: .issue(
                        GitLabIssueRoute(
                            projectID: 42,
                            issueIID: 7
                        )
                    ),
                    resourceID: 101,
                    title: "Baseline",
                    description: "Original",
                    updatedAt: .distantPast
                ),
            title: title,
            description: "Changed",
            revision: 1
        )
    }
}
