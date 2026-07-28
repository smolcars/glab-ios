import Foundation

nonisolated enum GitLabCredentialStoreError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case encoding
    case corruptData
    case keychain(status: Int32)

    var description: String {
        switch self {
        case .encoding:
            "Glab could not securely encode the GitLab session."
        case .corruptData:
            "The stored GitLab session is invalid. Sign in again."
        case let .keychain(status):
            "The iOS Keychain operation failed (status \(status))."
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }
}

nonisolated protocol GitLabCredentialStore: Sendable {
    func load(
        for accountID: GitLabAccountID
    ) async throws(GitLabCredentialStoreError) -> GitLabStoredSession?
    func save(_ session: GitLabStoredSession) async throws(GitLabCredentialStoreError)
    func replace(
        _ session: GitLabStoredSession,
        ifCurrentSessionIs expectedSession: GitLabStoredSession
    ) async throws(GitLabCredentialStoreError) -> Bool
    func delete(
        _ accountID: GitLabAccountID
    ) async throws(GitLabCredentialStoreError)
}

extension GitLabCredentialStore {
    func replace(
        _ session: GitLabStoredSession,
        ifCurrentSessionIs expectedSession: GitLabStoredSession
    ) async throws(GitLabCredentialStoreError) -> Bool {
        let accountID = GitLabAccountID(
            session: expectedSession
        )
        guard
            GitLabAccountID(session: session) == accountID,
            try await load(for: accountID)
                == expectedSession
        else {
            return false
        }

        try await save(session)
        return true
    }
}

actor InMemoryGitLabCredentialStore:
    GitLabCredentialStore,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    private var sessions:
        [GitLabAccountID: GitLabStoredSession]

    init(
        sessions: [GitLabStoredSession] = []
    ) {
        self.sessions = Dictionary(
            uniqueKeysWithValues: sessions.map {
                (GitLabAccountID(session: $0), $0)
            }
        )
    }

    init(
        session: GitLabStoredSession?
    ) {
        sessions = Dictionary(
            uniqueKeysWithValues:
                session.map {
                    [
                        (
                            GitLabAccountID(session: $0),
                            $0
                        ),
                    ]
                } ?? []
        )
    }

    nonisolated var description: String {
        "InMemoryGitLabCredentialStore(session: <redacted>)"
    }

    nonisolated var debugDescription: String {
        description
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

    func replace(
        _ session: GitLabStoredSession,
        ifCurrentSessionIs expectedSession: GitLabStoredSession
    ) async throws(GitLabCredentialStoreError) -> Bool {
        let accountID = GitLabAccountID(
            session: expectedSession
        )
        guard
            GitLabAccountID(session: session) == accountID,
            sessions[accountID] == expectedSession
        else {
            return false
        }

        sessions[accountID] = session
        return true
    }

    func delete(
        _ accountID: GitLabAccountID
    ) async throws(GitLabCredentialStoreError) {
        sessions[accountID] = nil
    }
}
