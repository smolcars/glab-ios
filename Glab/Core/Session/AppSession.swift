import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
    nonisolated enum AuthenticationNotice:
        Equatable,
        Sendable,
        CustomStringConvertible
    {
        case expiredOrRevoked

        var description: String {
            switch self {
            case .expiredOrRevoked:
                "Your GitLab session expired or was revoked. Sign in again."
            }
        }
    }

    nonisolated enum State:
        Equatable,
        Sendable,
        CustomStringConvertible,
        CustomDebugStringConvertible
    {
        case restoring
        case signedOut
        case signedIn(GitLabStoredSession)
        case failed(GitLabCredentialStoreError)

        var description: String {
            switch self {
            case .restoring:
                "restoring"
            case .signedOut:
                "signedOut"
            case let .signedIn(session):
                "signedIn(host: \(session.host.siteURL.absoluteString), "
                    + "username: \(session.user.username), credential: <redacted>)"
            case let .failed(error):
                "failed(\(error))"
            }
        }

        var debugDescription: String {
            description
        }
    }

    private(set) var state: State = .restoring
    private(set) var authenticationNotice:
        AuthenticationNotice?
    private(set) var accounts:
        [GitLabAccountSummary] = []
    private(set) var activeAccountID:
        GitLabAccountID?

    let credentialStore: any GitLabCredentialStore
    let responseCache: any GitLabResponseCaching
    let jobTraceStore:
        any GitLabJobTraceStoring
    let discussionDraftStore:
        any GitLabDiscussionDraftStoring
    let resourceEditDraftStore:
        any GitLabResourceEditDraftStoring
    let issueCreationDraftStore:
        any GitLabIssueCreationDraftStoring

    private let accountIndexStore:
        any GitLabAccountIndexStoring
    private let currentDate: () -> Date
    private var transitionSequence = 0

    var storedSession: GitLabStoredSession? {
        guard case let .signedIn(session) = state else {
            return nil
        }

        return session
    }

    init(
        credentialStore: any GitLabCredentialStore,
        accountIndexStore:
            any GitLabAccountIndexStoring =
                InMemoryGitLabAccountIndexStore(),
        responseCache: any GitLabResponseCaching =
            InMemoryGitLabResponseCache(),
        jobTraceStore:
            any GitLabJobTraceStoring =
                InMemoryGitLabJobTraceStore(),
        discussionDraftStore:
            any GitLabDiscussionDraftStoring =
                InMemoryGitLabDiscussionDraftStore(),
        resourceEditDraftStore:
            any GitLabResourceEditDraftStoring =
                InMemoryGitLabResourceEditDraftStore(),
        issueCreationDraftStore:
            any GitLabIssueCreationDraftStoring =
                InMemoryGitLabIssueCreationDraftStore(),
        currentDate: @escaping () -> Date = Date.init
    ) {
        self.credentialStore = credentialStore
        self.accountIndexStore = accountIndexStore
        self.responseCache = responseCache
        self.jobTraceStore = jobTraceStore
        self.discussionDraftStore =
            discussionDraftStore
        self.resourceEditDraftStore =
            resourceEditDraftStore
        self.issueCreationDraftStore =
            issueCreationDraftStore
        self.currentDate = currentDate
    }

    func restore() async {
        let transition = beginTransition()
        state = .restoring
        authenticationNotice = nil

        await jobTraceStore.prepare()
        guard isCurrent(transition) else {
            return
        }

        do {
            var index = try accountIndexStore.load()
            guard isCurrent(transition) else {
                return
            }

            publish(index)

            while let accountID = index.activeAccountID {
                let session = try await credentialStore.load(
                    for: accountID
                )
                guard isCurrent(transition) else {
                    return
                }

                if let session, canRestore(session) {
                    state = .signedIn(session)
                    return
                }

                if session != nil {
                    authenticationNotice =
                        .expiredOrRevoked
                    let deletionError:
                        GitLabCredentialStoreError?

                    do {
                        try await credentialStore.delete(
                            accountID
                        )
                        deletionError = nil
                    } catch {
                        deletionError = error
                    }

                    await purgeCaches(
                        for: accountID
                    )
                    guard isCurrent(transition) else {
                        return
                    }

                    if let deletionError {
                        state = .failed(deletionError)
                        return
                    }
                } else {
                    await purgeCaches(
                        for: accountID
                    )
                    guard isCurrent(transition) else {
                        return
                    }
                }

                index = try removing(
                    accountID,
                    from: index
                )
                try accountIndexStore.save(index)
                publish(index)
            }

            state = .signedOut
        } catch {
            guard isCurrent(transition) else {
                return
            }
            state = .failed(error)
        }
    }

    func establish(
        _ session: GitLabStoredSession
    ) async throws(GitLabCredentialStoreError) {
        let transition = beginTransition()
        let accountID = GitLabAccountID(
            session: session
        )
        let previousSession = try await credentialStore.load(
            for: accountID
        )
        guard isCurrent(transition) else {
            return
        }

        try await credentialStore.save(session)
        guard isCurrent(transition) else {
            await restoreCredential(
                previousSession,
                replacing: session
            )
            return
        }

        let currentIndex = try makeIndex()
        let updatedIndex: GitLabAccountIndex

        do {
            updatedIndex = try currentIndex.upserting(
                GitLabAccountSummary(session: session),
                makeActive: true
            )
            try accountIndexStore.save(updatedIndex)
        } catch {
            await restoreCredential(
                previousSession,
                replacing: session
            )
            throw .corruptData
        }

        guard isCurrent(transition) else {
            return
        }
        publish(updatedIndex)
        authenticationNotice = nil
        state = .signedIn(session)
    }

    func switchAccount(
        to accountID: GitLabAccountID
    ) async throws(GitLabCredentialStoreError) {
        guard
            accounts.contains(where: { $0.id == accountID })
        else {
            throw .corruptData
        }

        let transition = beginTransition()
        guard
            let session = try await credentialStore.load(
                for: accountID
            ),
            canRestore(session)
        else {
            throw .corruptData
        }
        guard isCurrent(transition) else {
            return
        }

        let updatedIndex: GitLabAccountIndex

        do {
            updatedIndex = try makeIndex().activating(
                accountID
            )
            try accountIndexStore.save(updatedIndex)
        } catch {
            throw .corruptData
        }

        publish(updatedIndex)
        authenticationNotice = nil
        state = .signedIn(session)
    }

    func removeAccount(
        _ accountID: GitLabAccountID
    ) async throws(GitLabCredentialStoreError) {
        try await removeAccount(
            accountID,
            removesDrafts: true
        )
    }

    private func removeAccount(
        _ accountID: GitLabAccountID,
        removesDrafts: Bool
    ) async throws(GitLabCredentialStoreError) {
        guard
            accounts.contains(where: { $0.id == accountID })
        else {
            return
        }

        let transition = beginTransition()
        let previousState = state
        let previousIndex = try makeIndex()
        let removedSession: GitLabStoredSession?

        if
            let activeSession = storedSession,
            GitLabAccountID(session: activeSession)
                == accountID
        {
            removedSession = activeSession
        } else {
            removedSession = try await credentialStore.load(
                for: accountID
            )
            guard isCurrent(transition) else {
                return
            }
        }

        let updatedIndex: GitLabAccountIndex

        do {
            updatedIndex = try previousIndex.removing(
                accountID
            )
            try accountIndexStore.save(updatedIndex)
        } catch {
            throw .corruptData
        }

        publish(updatedIndex)
        if previousIndex.activeAccountID == accountID {
            state = .restoring
        }

        do {
            if let removedSession {
                _ = try await credentialStore.delete(
                    accountID,
                    ifCurrentSessionIs: removedSession
                )
            }
        } catch {
            guard isCurrent(transition) else {
                return
            }
            try? accountIndexStore.save(
                previousIndex
            )
            publish(previousIndex)
            state = previousState
            throw error
        }

        if !accounts.contains(where: { $0.id == accountID }) {
            await purgeCaches(
                for: accountID,
                cancelIfAccountReturns: true
            )
            if removesDrafts {
                await discussionDraftStore
                    .removeAll(for: accountID)
                await resourceEditDraftStore
                    .removeAll(for: accountID)
                await issueCreationDraftStore
                    .removeAll(for: accountID)
            }
        }

        guard isCurrent(transition) else {
            return
        }

        guard
            previousIndex.activeAccountID
                == accountID
        else {
            return
        }

        guard
            let nextAccountID =
                updatedIndex.activeAccountID
        else {
            state = .signedOut
            return
        }

        do {
            guard
                let nextSession =
                    try await credentialStore.load(
                        for: nextAccountID
                    ),
                canRestore(nextSession)
            else {
                await restore()
                return
            }
            guard isCurrent(transition) else {
                return
            }

            state = .signedIn(nextSession)
        } catch {
            guard isCurrent(transition) else {
                return
            }
            state = .failed(error)
            throw error
        }
    }

    func signOut() async throws(GitLabCredentialStoreError) {
        guard let activeAccountID else {
            return
        }

        try await removeAccount(
            activeAccountID
        )
        if accounts.isEmpty {
            authenticationNotice = nil
        }
    }

    func invalidateAuthentication(
        _ notice: AuthenticationNotice,
        for accountID: GitLabAccountID
    ) async {
        guard activeAccountID == accountID else {
            return
        }

        authenticationNotice = notice

        do {
            try await removeAccount(
                accountID,
                removesDrafts: false
            )
        } catch {
            state = .failed(error)
        }
    }

    func handleAuthenticationFailure(
        _ error: GitLabSessionClientError,
        for accountID: GitLabAccountID
    ) async {
        guard error.requiresReauthentication else {
            return
        }

        await invalidateAuthentication(
            .expiredOrRevoked,
            for: accountID
        )
    }

    func dismissAuthenticationNotice() {
        authenticationNotice = nil
    }

    func synchronizeRefreshedSession(
        _ refreshedSession: GitLabStoredSession,
        for accountID: GitLabAccountID
    ) {
        guard
            activeAccountID == accountID,
            GitLabAccountID(
                session: refreshedSession
            ) == accountID,
            case let .signedIn(currentSession) = state,
            currentSession.host == refreshedSession.host,
            currentSession.user.id == refreshedSession.user.id,
            currentSession.oauthApplicationID
                == refreshedSession.oauthApplicationID,
            currentSession.credentialKind == .oauth,
            refreshedSession.credentialKind == .oauth
        else {
            return
        }

        state = .signedIn(refreshedSession)
    }

    private func canRestore(
        _ session: GitLabStoredSession
    ) -> Bool {
        guard
            session.credentialKind == .oauth,
            let expiresAt = session.oauthExpiresAt,
            expiresAt <= currentDate()
        else {
            return true
        }

        return session.canRefreshOAuth
    }

    private func makeIndex()
        throws(GitLabCredentialStoreError)
        -> GitLabAccountIndex
    {
        do {
            return try GitLabAccountIndex(
                accounts: accounts,
                activeAccountID: activeAccountID
            )
        } catch {
            throw .corruptData
        }
    }

    private func removing(
        _ accountID: GitLabAccountID,
        from index: GitLabAccountIndex
    ) throws(GitLabCredentialStoreError)
        -> GitLabAccountIndex
    {
        do {
            return try index.removing(accountID)
        } catch {
            throw .corruptData
        }
    }

    private func publish(
        _ index: GitLabAccountIndex
    ) {
        accounts = index.accounts
        activeAccountID = index.activeAccountID
    }

    private func purgeCaches(
        for accountID: GitLabAccountID,
        cancelIfAccountReturns: Bool = false
    ) async {
        await responseCache.removeAll(
            for: GitLabCacheAccount(
                host: accountID.host,
                userID: accountID.userID
            )
        )
        if
            cancelIfAccountReturns,
            accounts.contains(
                where: { $0.id == accountID }
            )
        {
            return
        }
        await jobTraceStore.removeAll(
            for: accountID
        )
    }

    private func restoreCredential(
        _ previousSession: GitLabStoredSession?,
        replacing savedSession: GitLabStoredSession
    ) async {
        if let previousSession {
            _ = try? await credentialStore.replace(
                previousSession,
                ifCurrentSessionIs: savedSession
            )
        } else {
            _ = try? await credentialStore.delete(
                GitLabAccountID(
                    session: savedSession
                ),
                ifCurrentSessionIs: savedSession
            )
        }
    }

    private func beginTransition() -> Int {
        transitionSequence &+= 1
        return transitionSequence
    }

    private func isCurrent(
        _ transition: Int
    ) -> Bool {
        transition == transitionSequence
    }
}
