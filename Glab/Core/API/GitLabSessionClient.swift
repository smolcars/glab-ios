import Foundation

nonisolated enum GitLabSessionClientError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case api(GitLabAPIError)
    case refresh(GitLabOAuthRefreshError)

    var description: String {
        switch self {
        case let .api(error):
            error.description
        case let .refresh(error):
            error.description
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }

    var requiresReauthentication: Bool {
        switch self {
        case .api(.unauthenticated),
             .refresh(.unavailable),
             .refresh(.token(.invalidGrant)):
            true
        default:
            false
        }
    }
}

nonisolated protocol GitLabSessionRequestSending: Sendable {
    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError) -> Response
}

nonisolated protocol GitLabPaginatedSessionRequestSending:
    GitLabSessionRequestSending
{
    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError) -> GitLabAPIResponse<Response>
}

actor GitLabSessionClient<Transport, TokenExchanger>
where
    Transport: GitLabHTTPTransport,
    TokenExchanger: GitLabOAuthTokenExchanging
{
    private let transport: Transport
    private let refreshCoordinator:
        GitLabOAuthRefreshCoordinator<TokenExchanger>
    private let sessionDidRefresh:
        @Sendable (GitLabStoredSession) async -> Void
    private var session: GitLabStoredSession

    init(
        session: GitLabStoredSession,
        transport: Transport,
        tokenExchanger: TokenExchanger,
        credentialStore: any GitLabCredentialStore,
        sessionDidRefresh:
            @escaping @Sendable (GitLabStoredSession) async -> Void = { _ in }
    ) {
        self.session = session
        self.transport = transport
        self.sessionDidRefresh = sessionDidRefresh
        refreshCoordinator = GitLabOAuthRefreshCoordinator(
            tokenExchanger: tokenExchanger,
            credentialStore: credentialStore
        )
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError) -> Response {
        try await sendResponse(endpoint).value
    }

    func sendResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError) -> GitLabAPIResponse<Response> {
        try await sendPage(.initial(endpoint))
    }

    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError) -> GitLabAPIResponse<Response> {
        try await refreshExpiredOAuthSession()

        let attemptedSession = session

        do {
            return try await client(for: attemptedSession).sendPage(page)
        } catch .unauthenticated where attemptedSession.credentialKind == .oauth {
            let retrySession: GitLabStoredSession

            if session.credential != attemptedSession.credential {
                retrySession = session
            } else {
                retrySession = try await refresh(attemptedSession)
            }

            do {
                return try await client(for: retrySession).sendPage(page)
            } catch {
                throw .api(error)
            }
        } catch {
            throw .api(error)
        }
    }

    func currentSession() -> GitLabStoredSession {
        session
    }

    private func refreshExpiredOAuthSession() async throws(GitLabSessionClientError) {
        guard
            session.credentialKind == .oauth,
            let expiresAt = session.oauthExpiresAt,
            expiresAt <= Date().addingTimeInterval(30)
        else {
            return
        }

        _ = try await refresh(session)
    }

    private func refresh(
        _ session: GitLabStoredSession
    ) async throws(GitLabSessionClientError) -> GitLabStoredSession {
        do {
            let refreshedSession = try await refreshCoordinator.refresh(session)
            self.session = refreshedSession
            await sessionDidRefresh(refreshedSession)
            return refreshedSession
        } catch {
            throw .refresh(error)
        }
    }

    private func client(
        for session: GitLabStoredSession
    ) -> GitLabClient<Transport> {
        GitLabClient(
            requestBuilder: GitLabRequestBuilder(
                host: session.host,
                authorization: session.credential.authorization
            ),
            transport: transport
        )
    }
}

extension GitLabSessionClient: GitLabSessionRequestSending {}
extension GitLabSessionClient: GitLabPaginatedSessionRequestSending {}
