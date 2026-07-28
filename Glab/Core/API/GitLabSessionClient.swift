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
    case insufficientAccess(
        required: GitLabAPIRequestAccess
    )

    var description: String {
        switch self {
        case let .api(error):
            error.description
        case let .refresh(error):
            error.description
        case .insufficientAccess:
            "This action requires GitLab API write access. "
                + "Sign in with OAuth or a personal access token "
                + "that includes the api scope."
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

    func loadResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>,
        cachePolicy: GitLabResponseCachePolicy,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<Response>
            ) async -> Void
    ) async throws(GitLabSessionClientError)

    func invalidateCachedResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async
}

nonisolated protocol GitLabPaginatedSessionRequestSending:
    GitLabSessionRequestSending
{
    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError) -> GitLabAPIResponse<Response>

    func loadPage<Response>(
        _ page: GitLabAPIPageRequest<Response>,
        cachePolicy: GitLabResponseCachePolicy,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<Response>
            ) async -> Void
    ) async throws(GitLabSessionClientError)
}

extension GitLabSessionRequestSending {
    func loadResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>,
        cachePolicy: GitLabResponseCachePolicy,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<Response>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let value = try await send(endpoint)
        await onResponse(
            GitLabAPIResponseEvent(
                value: value,
                metadata: GitLabResponseMetadata(),
                source: .network
            )
        )
    }

    func invalidateCachedResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async {}
}

extension GitLabPaginatedSessionRequestSending {
    func loadPage<Response>(
        _ page: GitLabAPIPageRequest<Response>,
        cachePolicy: GitLabResponseCachePolicy,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<Response>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let response = try await sendPage(page)
        await onResponse(
            GitLabAPIResponseEvent(
                value: response.value,
                metadata: response.metadata,
                source: .network
            )
        )
    }
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
    private let responseCache:
        (any GitLabResponseCaching)?
    private let readCoalescer =
        GitLabReadRequestCoalescer()
    private let currentDate:
        @Sendable () -> Date
    private var session: GitLabStoredSession

    init(
        session: GitLabStoredSession,
        transport: Transport,
        tokenExchanger: TokenExchanger,
        credentialStore: any GitLabCredentialStore,
        responseCache:
            (any GitLabResponseCaching)? = nil,
        currentDate:
            @escaping @Sendable () -> Date = Date.init,
        sessionDidRefresh:
            @escaping @Sendable (GitLabStoredSession) async -> Void = { _ in }
    ) {
        self.session = session
        self.transport = transport
        self.responseCache = responseCache
        self.currentDate = currentDate
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

    func loadResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>,
        cachePolicy: GitLabResponseCachePolicy,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<Response>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await loadPage(
            .initial(endpoint),
            cachePolicy: cachePolicy,
            refreshBehavior: refreshBehavior,
            onResponse: onResponse
        )
    }

    func invalidateCachedResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async {
        guard
            let responseCache,
            let key = cacheKey(
                for: GitLabAPIPageRequest
                    .initial(endpoint)
            )
        else {
            return
        }

        await responseCache.remove(for: key)
    }

    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError) -> GitLabAPIResponse<Response> {
        try ensureAccess(for: page)

        let rawResponse = try await sendRawPage(
            page
        )

        do {
            return try GitLabAPIResponseDecoder.decode(
                rawResponse
            )
        } catch {
            throw .api(error)
        }
    }

    func loadPage<Response>(
        _ page: GitLabAPIPageRequest<Response>,
        cachePolicy: GitLabResponseCachePolicy,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<Response>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try ensureAccess(for: page)

        let key = cacheKey(for: page)
        var cachedForRevalidation:
            GitLabCachedResponse?
        var decodedCached:
            GitLabAPIResponse<Response>?

        if
            let responseCache,
            let key,
            let cached = await responseCache.response(
                for: key
            )
        {
            let freshness = cached.freshness(
                at: currentDate(),
                policy: cachePolicy
            )

            switch freshness {
            case .expired:
                await responseCache.remove(for: key)
            case .fresh, .stale:
                if let response:
                    GitLabAPIResponse<Response> =
                    decodedCachedResponse(cached)
                {
                    cachedForRevalidation = cached
                    decodedCached = response

                    guard
                        refreshBehavior == .ifStale
                    else {
                        break
                    }

                    await onResponse(
                        GitLabAPIResponseEvent(
                            value: response.value,
                            metadata: response.metadata,
                            source:
                                .cache(freshness),
                            cacheStoredAt:
                                cached.storedAt
                        )
                    )

                    if freshness == .fresh {
                        return
                    }
                } else {
                    await responseCache.remove(
                        for: key
                    )
                }
            }
        }

        guard !Task.isCancelled else {
            throw .api(.cancelled)
        }

        let rawResponse = try await loadRawPage(
            page,
            key: key,
            validators:
                cachedForRevalidation.map {
                    GitLabConditionalRequestValidators(
                        entityTag: $0.entityTag,
                        lastModified: $0.lastModified
                    )
                }
        )

        if rawResponse.isNotModified {
            guard
                let cached = cachedForRevalidation,
                let response = decodedCached,
                let responseCache,
                let key
            else {
                throw .api(.invalidResponse)
            }

            let date = currentDate()
            try? await responseCache.store(
                GitLabCachedResponse(
                    body: cached.body,
                    nextPageURL:
                        cached.nextPageURL,
                    totalCount:
                        cached.totalCount,
                    entityTag:
                        rawResponse.entityTag
                        ?? cached.entityTag,
                    lastModified:
                        rawResponse.lastModified
                        ?? cached.lastModified,
                    storedAt: date,
                    lastAccessedAt: date
                ),
                for: key
            )
            await onResponse(
                GitLabAPIResponseEvent(
                    value: response.value,
                    metadata: response.metadata,
                    source: .network
                )
            )
            return
        }

        let response: GitLabAPIResponse<Response>

        do {
            response = try GitLabAPIResponseDecoder
                .decode(rawResponse)
        } catch {
            throw .api(error)
        }

        if
            let responseCache,
            let key
        {
            let date = currentDate()
            try? await responseCache.store(
                GitLabCachedResponse(
                    body: rawResponse.body,
                    nextPageURL:
                        rawResponse.metadata
                            .nextPageURL,
                    totalCount:
                        rawResponse.metadata
                            .totalCount,
                    entityTag:
                        rawResponse.entityTag,
                    lastModified:
                        rawResponse.lastModified,
                    storedAt: date,
                    lastAccessedAt: date
                ),
                for: key
            )
        }

        await onResponse(
            GitLabAPIResponseEvent(
                value: response.value,
                metadata: response.metadata,
                source: .network
            )
        )
    }

    func currentSession() -> GitLabStoredSession {
        session
    }

    private func ensureAccess<Response>(
        for page: GitLabAPIPageRequest<Response>
    ) throws(GitLabSessionClientError) {
        guard
            page.requiredAccess == .read
                || session.apiAccess.canWrite
        else {
            throw .insufficientAccess(
                required: page.requiredAccess
            )
        }
    }

    private func sendRawPage<Response>(
        _ page: GitLabAPIPageRequest<Response>,
        validators:
            GitLabConditionalRequestValidators? = nil
    ) async throws(GitLabSessionClientError)
        -> GitLabRawAPIResponse
    {
        try await refreshExpiredOAuthSession()

        let attemptedSession = session

        do {
            return try await client(
                for: attemptedSession
            ).sendRawPage(
                page,
                validators: validators
            )
        } catch .unauthenticated where attemptedSession.credentialKind == .oauth {
            let retrySession: GitLabStoredSession

            if session.credential != attemptedSession.credential {
                retrySession = session
            } else {
                retrySession = try await refresh(attemptedSession)
            }

            do {
                return try await client(
                    for: retrySession
                ).sendRawPage(
                    page,
                    validators: validators
                )
            } catch {
                throw .api(error)
            }
        } catch {
            throw .api(error)
        }
    }

    private func loadRawPage<Response>(
        _ page: GitLabAPIPageRequest<Response>,
        key: GitLabResponseCacheKey?,
        validators:
            GitLabConditionalRequestValidators?
    ) async throws(GitLabSessionClientError)
        -> GitLabRawAPIResponse
    {
        guard let key else {
            return try await sendRawPage(
                page,
                validators: validators
            )
        }

        let outcome = await readCoalescer.response(
            for: key
        ) { [weak self] in
            guard let self else {
                return .failure(
                    .api(.cancelled)
                )
            }

            do {
                return .success(
                    try await self.sendRawPage(
                        page,
                        validators: validators
                    )
                )
            } catch let error as GitLabSessionClientError {
                return .failure(error)
            } catch {
                return .failure(
                    .api(.transport)
                )
            }
        }

        switch outcome {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }

    private func cacheKey<Response>(
        for page: GitLabAPIPageRequest<Response>
    ) -> GitLabResponseCacheKey? {
        guard
            case let .initial(endpoint) = page,
            endpoint.method == .get,
            let request = try? client(
                for: session
            ).request(for: page),
            let requestURL = request.url
        else {
            return nil
        }

        return GitLabResponseCacheKey(
            account: GitLabCacheAccount(
                session: session
            ),
            requestURL: requestURL
        )
    }

    private func decodedCachedResponse<Response>(
        _ cached: GitLabCachedResponse
    ) -> GitLabAPIResponse<Response>?
    where Response: Decodable & Sendable {
        try? GitLabAPIResponseDecoder.decode(
            GitLabRawAPIResponse(
                body: cached.body,
                metadata: GitLabResponseMetadata(
                    nextPageURL:
                        cached.nextPageURL,
                    totalCount:
                        cached.totalCount
                ),
                entityTag: cached.entityTag,
                lastModified: cached.lastModified
            )
        )
    }

    private func refreshExpiredOAuthSession() async throws(GitLabSessionClientError) {
        guard
            session.credentialKind == .oauth,
            let expiresAt = session.oauthExpiresAt,
            expiresAt
                <= currentDate()
                    .addingTimeInterval(30)
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
