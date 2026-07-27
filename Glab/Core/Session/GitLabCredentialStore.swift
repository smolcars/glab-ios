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
    func load() async throws(GitLabCredentialStoreError) -> GitLabStoredSession?
    func save(_ session: GitLabStoredSession) async throws(GitLabCredentialStoreError)
    func delete() async throws(GitLabCredentialStoreError)
}

actor InMemoryGitLabCredentialStore:
    GitLabCredentialStore,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    private var session: GitLabStoredSession?

    init(session: GitLabStoredSession? = nil) {
        self.session = session
    }

    nonisolated var description: String {
        "InMemoryGitLabCredentialStore(session: <redacted>)"
    }

    nonisolated var debugDescription: String {
        description
    }

    func load() async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
        session
    }

    func save(
        _ session: GitLabStoredSession
    ) async throws(GitLabCredentialStoreError) {
        self.session = session
    }

    func delete() async throws(GitLabCredentialStoreError) {
        session = nil
    }
}
