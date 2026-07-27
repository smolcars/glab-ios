import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
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
    private let credentialStore: any GitLabCredentialStore

    var storedSession: GitLabStoredSession? {
        guard case let .signedIn(session) = state else {
            return nil
        }

        return session
    }

    init(credentialStore: any GitLabCredentialStore) {
        self.credentialStore = credentialStore
    }

    func restore() async {
        state = .restoring

        do {
            if let session = try await credentialStore.load() {
                state = .signedIn(session)
            } else {
                state = .signedOut
            }
        } catch {
            state = .failed(error)
        }
    }

    func establish(
        _ session: GitLabStoredSession
    ) async throws(GitLabCredentialStoreError) {
        try await credentialStore.save(session)
        state = .signedIn(session)
    }

    func signOut() async throws(GitLabCredentialStoreError) {
        try await credentialStore.delete()
        state = .signedOut
    }
}
