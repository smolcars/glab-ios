import Foundation

nonisolated protocol GitLabMergeRequestLoading: Sendable {
    func loadMergeRequestsPage(
        for mode: GitLabMergeRequestListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestPage

    func loadMergeRequestsFirstPage(
        for mode: GitLabMergeRequestListMode,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabMergeRequest
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)

    func loadMergeRequest(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequest

    func loadMergeRequest(
        at route: GitLabMergeRequestRoute,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabMergeRequest
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)
}

extension GitLabMergeRequestLoading {
    func loadMergeRequestsFirstPage(
        for mode: GitLabMergeRequestListMode,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabMergeRequest
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let page = try await loadMergeRequestsPage(
            for: mode,
            after: nil
        )
        await onPage(
            GitLabResourcePageEvent(
                page: GitLabResourcePage(
                    items: page.mergeRequests,
                    nextPageURL: page.nextPageURL
                ),
                source: .network
            )
        )
    }

    func loadMergeRequest(
        at route: GitLabMergeRequestRoute,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabMergeRequest
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        await onResponse(
            GitLabAPIResponseEvent(
                value:
                    try await loadMergeRequest(
                        at: route
                    ),
                metadata: GitLabResponseMetadata(),
                source: .network
            )
        )
    }
}

nonisolated protocol
    GitLabMergeRequestApprovalLoading:
    Sendable
{
    func loadMergeRequestApproval(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalAvailability

    func loadMergeRequestApproval(
        at route: GitLabMergeRequestRoute,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabMergeRequestApprovalAvailability
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)
}

extension GitLabMergeRequestApprovalLoading {
    func loadMergeRequestApproval(
        at route: GitLabMergeRequestRoute,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabMergeRequestApprovalAvailability
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        await onResponse(
            GitLabAPIResponseEvent(
                value:
                    try await loadMergeRequestApproval(
                        at: route
                    ),
                metadata: GitLabResponseMetadata(),
                source: .network
            )
        )
    }
}

nonisolated struct GitLabMergeRequestDiffPage:
    Equatable,
    Sendable
{
    let files: [GitLabMergeRequestDiffFile]
    let nextPageURL: URL?
    let totalCount: Int?
}

nonisolated protocol GitLabMergeRequestDiffLoading:
    Sendable
{
    func loadMergeRequestDiffsPage(
        at route: GitLabMergeRequestRoute,
        headSHA: String,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestDiffPage

    func loadMergeRequestDiffsFirstPage(
        at route: GitLabMergeRequestRoute,
        headSHA: String,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabMergeRequestDiffFile
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)
}

extension GitLabMergeRequestDiffLoading {
    func loadMergeRequestDiffsFirstPage(
        at route: GitLabMergeRequestRoute,
        headSHA: String,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabMergeRequestDiffFile
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let page = try await loadMergeRequestDiffsPage(
            at: route,
            headSHA: headSHA,
            after: nil
        )
        await onPage(
            GitLabResourcePageEvent(
                page: GitLabResourcePage(
                    items: page.files,
                    nextPageURL: page.nextPageURL,
                    totalCount: page.totalCount
                ),
                source: .network
            )
        )
    }
}

nonisolated struct LiveGitLabMergeRequestLoader:
    GitLabMergeRequestLoading,
    GitLabMergeRequestApprovalLoading,
    GitLabMergeRequestDiffLoading,
    Sendable
{
    private let client:
        any GitLabPaginatedSessionRequestSending

    init(
        client: any GitLabPaginatedSessionRequestSending
    ) {
        self.client = client
    }

    @concurrent
    func loadMergeRequestsPage(
        for mode: GitLabMergeRequestListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestPage
    {
        let request: GitLabAPIPageRequest<
            [GitLabMergeRequest]
        > =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(
                    GitLabMergeRequestEndpoints
                        .mergeRequests(for: mode)
                )
            }
        let response = try await client.sendPage(request)

        return GitLabMergeRequestPage(
            mergeRequests: response.value,
            nextPageURL: response.metadata.nextPageURL
        )
    }

    @concurrent
    func loadMergeRequestsFirstPage(
        for mode: GitLabMergeRequestListMode,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabMergeRequest
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadPage(
            .initial(
                GitLabMergeRequestEndpoints
                    .mergeRequests(for: mode)
            ),
            cachePolicy: .workList,
            refreshBehavior: refreshBehavior
        ) {
            await onPage(
                GitLabResourcePageEvent(
                    apiResponse: $0
                )
            )
        }
    }

    @concurrent
    func loadMergeRequest(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequest
    {
        try await client.send(
            GitLabMergeRequestEndpoints.mergeRequest(
                at: route
            )
        )
    }

    @concurrent
    func loadMergeRequest(
        at route: GitLabMergeRequestRoute,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabMergeRequest
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadResponse(
            GitLabMergeRequestEndpoints
                .mergeRequest(at: route),
            cachePolicy: .mergeRequestReadiness,
            refreshBehavior: refreshBehavior,
            onResponse: onResponse
        )
    }

    @concurrent
    func loadMergeRequestApproval(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalAvailability
    {
        do {
            return .available(
                try await client.send(
                    GitLabMergeRequestEndpoints
                        .approvals(at: route)
                )
            )
        } catch .api(.forbidden),
                .api(.notFound)
        {
            return .unavailable
        } catch {
            throw error
        }
    }

    @concurrent
    func loadMergeRequestApproval(
        at route: GitLabMergeRequestRoute,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabMergeRequestApprovalAvailability
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        do {
            try await client.loadResponse(
                GitLabMergeRequestEndpoints
                    .approvals(at: route),
                cachePolicy:
                    .mergeRequestReadiness,
                refreshBehavior:
                    refreshBehavior
            ) { event in
                await onResponse(
                    GitLabAPIResponseEvent(
                        value:
                            .available(
                                event.value
                            ),
                        metadata:
                            event.metadata,
                        source: event.source,
                        cacheStoredAt:
                            event.cacheStoredAt
                    )
                )
            }
        } catch .api(.forbidden),
                .api(.notFound)
        {
            await onResponse(
                GitLabAPIResponseEvent(
                    value: .unavailable,
                    metadata:
                        GitLabResponseMetadata(),
                    source: .network
                )
            )
        } catch {
            throw error
        }
    }

    @concurrent
    func loadMergeRequestDiffsPage(
        at route: GitLabMergeRequestRoute,
        headSHA: String,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestDiffPage
    {
        let request: GitLabAPIPageRequest<
            [GitLabMergeRequestDiffFile]
        > =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(
                    GitLabMergeRequestDiffEndpoints
                        .diffs(
                            at: route,
                            headSHA: headSHA
                        )
                )
            }
        let response = try await client.sendPage(
            request
        )
        return GitLabMergeRequestDiffPage(
            files: response.value,
            nextPageURL:
                response.metadata.nextPageURL,
            totalCount:
                response.metadata.totalCount
        )
    }

    @concurrent
    func loadMergeRequestDiffsFirstPage(
        at route: GitLabMergeRequestRoute,
        headSHA: String,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabMergeRequestDiffFile
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadPage(
            .initial(
                GitLabMergeRequestDiffEndpoints
                    .diffs(
                        at: route,
                        headSHA: headSHA
                    )
            ),
            cachePolicy: .mergeRequestDiffs,
            refreshBehavior: refreshBehavior
        ) {
            await onPage(
                GitLabResourcePageEvent(
                    apiResponse: $0
                )
            )
        }
    }
}
