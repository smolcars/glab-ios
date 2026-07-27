import Foundation

nonisolated enum GitLabOAuthRefreshError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case unavailable
    case configuration(GitLabOAuthConfigurationError)
    case token(GitLabOAuthTokenError)
    case invalidSession
    case storage(GitLabCredentialStoreError)

    var description: String {
        switch self {
        case .unavailable:
            "This GitLab session cannot be refreshed. Sign in again."
        case let .configuration(error):
            error.description
        case let .token(error):
            error.description
        case .invalidSession:
            "GitLab returned credentials that could not replace this session."
        case let .storage(error):
            error.description
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }
}

actor GitLabOAuthRefreshCoordinator<TokenExchanger>
where TokenExchanger: GitLabOAuthTokenExchanging
{
    private struct InFlightRefresh {
        let id: UUID
        let task: Task<GitLabStoredSession, any Error>
    }

    private let tokenExchanger: TokenExchanger
    private let credentialStore: any GitLabCredentialStore
    private var inFlightRefresh: InFlightRefresh?

    init(
        tokenExchanger: TokenExchanger,
        credentialStore: any GitLabCredentialStore
    ) {
        self.tokenExchanger = tokenExchanger
        self.credentialStore = credentialStore
    }

    func refresh(
        _ session: GitLabStoredSession
    ) async throws(GitLabOAuthRefreshError) -> GitLabStoredSession {
        if let inFlightRefresh {
            return try await value(from: inFlightRefresh)
        }

        guard
            session.credentialKind == .oauth,
            let refreshToken = session.credential.oauthRefreshToken,
            let applicationID = session.oauthApplicationID
        else {
            throw .unavailable
        }

        let configuration: GitLabOAuthConfiguration

        do {
            configuration = try GitLabOAuthConfiguration(
                instanceURL: session.host.siteURL.absoluteString,
                applicationID: applicationID
            )
        } catch {
            throw .configuration(error)
        }

        let refreshID = UUID()
        let task = Task { [credentialStore, tokenExchanger] in
            let credential: GitLabCredential

            do {
                credential = try await tokenExchanger.refresh(
                    configuration: configuration,
                    refreshToken: refreshToken
                )
            } catch let error as GitLabOAuthTokenError {
                throw GitLabOAuthRefreshError.token(error)
            } catch {
                throw GitLabOAuthRefreshError.invalidSession
            }

            let updatedSession: GitLabStoredSession

            do {
                updatedSession = try session.replacingOAuthCredential(credential)
            } catch {
                throw GitLabOAuthRefreshError.invalidSession
            }

            do {
                let replaced = try await credentialStore.replace(
                    updatedSession,
                    ifCurrentSessionIs: session
                )
                guard replaced else {
                    throw GitLabOAuthRefreshError.invalidSession
                }
            } catch let error as GitLabCredentialStoreError {
                throw GitLabOAuthRefreshError.storage(error)
            } catch let error as GitLabOAuthRefreshError {
                throw error
            } catch {
                throw GitLabOAuthRefreshError.invalidSession
            }

            return updatedSession
        }
        let inFlightRefresh = InFlightRefresh(id: refreshID, task: task)
        self.inFlightRefresh = inFlightRefresh
        return try await value(from: inFlightRefresh)
    }

    private func value(
        from inFlightRefresh: InFlightRefresh
    ) async throws(GitLabOAuthRefreshError) -> GitLabStoredSession {
        do {
            let session = try await inFlightRefresh.task.value
            clearRefresh(id: inFlightRefresh.id)
            return session
        } catch let error as GitLabOAuthRefreshError {
            clearRefresh(id: inFlightRefresh.id)
            throw error
        } catch {
            clearRefresh(id: inFlightRefresh.id)
            throw .invalidSession
        }
    }

    private func clearRefresh(id: UUID) {
        guard inFlightRefresh?.id == id else {
            return
        }
        inFlightRefresh = nil
    }
}
