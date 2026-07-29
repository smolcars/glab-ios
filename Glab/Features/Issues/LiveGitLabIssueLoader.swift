import Foundation

nonisolated protocol GitLabIssueLoading: Sendable {
    func loadAssignedIssuesPage(
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError) -> GitLabIssuePage

    func loadAssignedIssuesFirstPage(
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<GitLabIssue>
            ) async -> Void
    ) async throws(GitLabSessionClientError)

    func loadProjectIssuesPage(
        projectID: Int,
        state: GitLabProjectIssueState,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabIssue>

    func loadProjectIssuesFirstPage(
        projectID: Int,
        state: GitLabProjectIssueState,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabIssue
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)

    func loadIssue(
        at route: GitLabIssueRoute
    ) async throws(GitLabSessionClientError) -> GitLabIssue

    func loadIssue(
        at route: GitLabIssueRoute,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<GitLabIssue>
            ) async -> Void
    ) async throws(GitLabSessionClientError)
}

extension GitLabIssueLoading {
    func loadProjectIssuesPage(
        projectID: Int,
        state: GitLabProjectIssueState,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabIssue>
    {
        throw .api(.invalidResponse)
    }

    func loadProjectIssuesFirstPage(
        projectID: Int,
        state: GitLabProjectIssueState,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabIssue
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let page = try await loadProjectIssuesPage(
            projectID: projectID,
            state: state,
            after: nil
        )
        await onPage(
            GitLabResourcePageEvent(
                page: page,
                source: .network
            )
        )
    }

    func loadAssignedIssuesFirstPage(
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<GitLabIssue>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let page = try await loadAssignedIssuesPage(
            after: nil
        )
        await onPage(
            GitLabResourcePageEvent(
                page: GitLabResourcePage(
                    items: page.issues,
                    nextPageURL: page.nextPageURL
                ),
                source: .network
            )
        )
    }

    func loadIssue(
        at route: GitLabIssueRoute,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<GitLabIssue>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        await onResponse(
            GitLabAPIResponseEvent(
                value: try await loadIssue(at: route),
                metadata: GitLabResponseMetadata(),
                source: .network
            )
        )
    }
}

nonisolated struct LiveGitLabIssueLoader:
    GitLabIssueLoading,
    Sendable
{
    private let client: any GitLabPaginatedSessionRequestSending

    init(client: any GitLabPaginatedSessionRequestSending) {
        self.client = client
    }

    @concurrent
    func loadAssignedIssuesPage(
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError) -> GitLabIssuePage {
        let request: GitLabAPIPageRequest<[GitLabIssue]> =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(GitLabIssueEndpoints.assignedIssues)
            }
        let response = try await client.sendPage(request)

        return GitLabIssuePage(
            issues: response.value,
            nextPageURL: response.metadata.nextPageURL
        )
    }

    @concurrent
    func loadAssignedIssuesFirstPage(
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<GitLabIssue>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadPage(
            .initial(
                GitLabIssueEndpoints.assignedIssues
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
    func loadProjectIssuesPage(
        projectID: Int,
        state: GitLabProjectIssueState,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabIssue>
    {
        let request:
            GitLabAPIPageRequest<
                [GitLabIssue]
            > =
                if let nextPageURL {
                    .next(nextPageURL)
                } else {
                    .initial(
                        GitLabIssueEndpoints
                            .projectIssues(
                                projectID:
                                    projectID,
                                state: state
                            )
                    )
                }
        let response =
            try await client.sendPage(request)

        return GitLabResourcePage(
            items: response.value,
            nextPageURL:
                response.metadata.nextPageURL,
            totalCount:
                response.metadata.totalCount
        )
    }

    @concurrent
    func loadProjectIssuesFirstPage(
        projectID: Int,
        state: GitLabProjectIssueState,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabIssue
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadPage(
            .initial(
                GitLabIssueEndpoints
                    .projectIssues(
                        projectID: projectID,
                        state: state
                    )
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
    func loadIssue(
        at route: GitLabIssueRoute
    ) async throws(GitLabSessionClientError) -> GitLabIssue {
        try await client.send(
            GitLabIssueEndpoints.issue(at: route)
        )
    }

    @concurrent
    func loadIssue(
        at route: GitLabIssueRoute,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<GitLabIssue>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadResponse(
            GitLabIssueEndpoints.issue(at: route),
            cachePolicy: .workItemDetail,
            refreshBehavior: refreshBehavior,
            onResponse: onResponse
        )
    }
}
