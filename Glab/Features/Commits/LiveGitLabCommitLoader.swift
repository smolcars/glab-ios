import Foundation

nonisolated protocol GitLabCommitLoading:
    Sendable
{
    func loadCommitsPage(
        projectID: Int,
        refName: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabCommitPage

    func loadCommitsFirstPage(
        projectID: Int,
        refName: String?,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabCommit
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)

    func loadCommitDiff(
        at route: GitLabCommitDiffRoute
    ) async throws(GitLabSessionClientError)
        -> [GitLabDiffFile]

    func loadCommitDiff(
        at route: GitLabCommitDiffRoute,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    [GitLabDiffFile]
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)
}

extension GitLabCommitLoading {
    func loadCommitsFirstPage(
        projectID: Int,
        refName: String?,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabCommit
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let page = try await loadCommitsPage(
            projectID: projectID,
            refName: refName,
            after: nil
        )
        await onPage(
            GitLabResourcePageEvent(
                page: GitLabResourcePage(
                    items: page.commits,
                    nextPageURL:
                        page.nextPageURL
                ),
                source: .network
            )
        )
    }

    func loadCommitDiff(
        at route: GitLabCommitDiffRoute,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    [GitLabDiffFile]
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let files = try await loadCommitDiff(
            at: route
        )
        await onResponse(
            GitLabAPIResponseEvent(
                value: files,
                metadata:
                    GitLabResponseMetadata(),
                source: .network
            )
        )
    }
}

nonisolated struct LiveGitLabCommitLoader:
    GitLabCommitLoading,
    Sendable
{
    private let client:
        any GitLabPaginatedSessionRequestSending

    init(
        client:
            any GitLabPaginatedSessionRequestSending
    ) {
        self.client = client
    }

    @concurrent
    func loadCommitsPage(
        projectID: Int,
        refName: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabCommitPage
    {
        let request:
            GitLabAPIPageRequest<
                [GitLabCommit]
            > =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(
                    GitLabCommitEndpoints
                        .commits(
                            projectID:
                                projectID,
                            refName: refName
                        )
                )
            }
        let response = try await client
            .sendPage(request)

        return GitLabCommitPage(
            commits: response.value,
            nextPageURL:
                response.metadata.nextPageURL
        )
    }

    @concurrent
    func loadCommitsFirstPage(
        projectID: Int,
        refName: String?,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabCommit
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadPage(
            .initial(
                GitLabCommitEndpoints
                    .commits(
                        projectID: projectID,
                        refName: refName
                    )
            ),
            cachePolicy: .commitHistory,
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
    func loadCommitDiff(
        at route: GitLabCommitDiffRoute
    ) async throws(GitLabSessionClientError)
        -> [GitLabDiffFile]
    {
        try await client.send(
            GitLabCommitEndpoints.diff(
                projectID: route.projectID,
                commitSHA: route.commitSHA
            )
        )
    }

    @concurrent
    func loadCommitDiff(
        at route: GitLabCommitDiffRoute,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    [GitLabDiffFile]
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadResponse(
            GitLabCommitEndpoints.diff(
                projectID: route.projectID,
                commitSHA: route.commitSHA
            ),
            cachePolicy: .commitDiff,
            refreshBehavior: refreshBehavior,
            onResponse: onResponse
        )
    }
}
