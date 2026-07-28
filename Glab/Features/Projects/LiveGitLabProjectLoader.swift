import Foundation

nonisolated protocol GitLabProjectLoading: Sendable {
    func loadProjectsPage(
        for mode: GitLabProjectListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabProjectPage

    func loadProjectsFirstPage(
        for mode: GitLabProjectListMode,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<GitLabProject>
            ) async -> Void
    ) async throws(GitLabSessionClientError)
}

extension GitLabProjectLoading {
    func loadProjectsFirstPage(
        for mode: GitLabProjectListMode,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<GitLabProject>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let page = try await loadProjectsPage(
            for: mode,
            after: nil
        )
        await onPage(
            GitLabResourcePageEvent(
                page: GitLabResourcePage(
                    items: page.projects,
                    nextPageURL: page.nextPageURL
                ),
                source: .network
            )
        )
    }
}

nonisolated struct LiveGitLabProjectLoader:
    GitLabProjectLoading,
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
    func loadProjectsPage(
        for mode: GitLabProjectListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabProjectPage
    {
        let request: GitLabAPIPageRequest<[GitLabProject]> =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(
                    GitLabProjectEndpoints.projects(
                        for: mode
                    )
                )
            }
        let response = try await client.sendPage(request)

        return GitLabProjectPage(
            projects: response.value,
            nextPageURL: response.metadata.nextPageURL
        )
    }

    @concurrent
    func loadProjectsFirstPage(
        for mode: GitLabProjectListMode,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<GitLabProject>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadPage(
            .initial(
                GitLabProjectEndpoints.projects(
                    for: mode
                )
            ),
            cachePolicy: .projects,
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
}
