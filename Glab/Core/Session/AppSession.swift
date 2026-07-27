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
    private(set) var authenticationNotice: AuthenticationNotice?
    private let credentialStore: any GitLabCredentialStore
    private let currentDate: () -> Date

    var storedSession: GitLabStoredSession? {
        guard case let .signedIn(session) = state else {
            return nil
        }

        return session
    }

    init(
        credentialStore: any GitLabCredentialStore,
        currentDate: @escaping () -> Date = Date.init
    ) {
        self.credentialStore = credentialStore
        self.currentDate = currentDate
    }

    func restore() async {
        state = .restoring
        authenticationNotice = nil

        do {
            if let session = try await credentialStore.load() {
                if canRestore(session) {
                    state = .signedIn(session)
                } else {
                    authenticationNotice = .expiredOrRevoked
                    try await credentialStore.delete()
                    state = .signedOut
                }
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
        authenticationNotice = nil
        state = .signedIn(session)
    }

    func signOut() async throws(GitLabCredentialStoreError) {
        try await credentialStore.delete()
        authenticationNotice = nil
        state = .signedOut
    }

    func invalidateAuthentication(
        _ notice: AuthenticationNotice
    ) async {
        authenticationNotice = notice

        do {
            try await credentialStore.delete()
            state = .signedOut
        } catch {
            state = .failed(error)
        }
    }

    private func canRestore(_ session: GitLabStoredSession) -> Bool {
        guard
            session.credentialKind == .oauth,
            let expiresAt = session.oauthExpiresAt,
            expiresAt <= currentDate()
        else {
            return true
        }

        return session.canRefreshOAuth
    }
}
