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

    func loadIssue(
        at route: GitLabIssueRoute
    ) async throws(GitLabSessionClientError) -> GitLabIssue
}

extension GitLabIssueLoading {
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
                    page: GitLabResourcePage(
                        items: $0.value,
                        nextPageURL:
                            $0.metadata.nextPageURL,
                        totalCount:
                            $0.metadata.totalCount
                    ),
                    source: $0.source,
                    cacheStoredAt:
                        $0.cacheStoredAt
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
}
