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

nonisolated struct LiveGitLabMergeRequestLoader:
    GitLabMergeRequestLoading,
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
            cachePolicy: .workItemDetail,
            refreshBehavior: refreshBehavior,
            onResponse: onResponse
        )
    }
}
