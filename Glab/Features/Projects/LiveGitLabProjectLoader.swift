import Foundation

nonisolated protocol GitLabProjectResolving:
    Sendable
{
    func loadProject(
        pathWithNamespace: String
    ) async throws(GitLabSessionClientError)
        -> GitLabProject

    func loadProject(
        pathWithNamespace: String,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabProject
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)
}

extension GitLabProjectResolving {
    func loadProject(
        pathWithNamespace: String,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabProject
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let project = try await loadProject(
            pathWithNamespace:
                pathWithNamespace
        )
        await onResponse(
            GitLabAPIResponseEvent(
                value: project,
                metadata:
                    GitLabResponseMetadata(),
                source: .network
            )
        )
    }
}

nonisolated protocol GitLabProjectLoading:
    Sendable
{
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
    GitLabProjectResolving,
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
    func loadProject(
        pathWithNamespace: String
    ) async throws(GitLabSessionClientError)
        -> GitLabProject
    {
        try await client.send(
            GitLabProjectEndpoints.project(
                pathWithNamespace:
                    pathWithNamespace
            )
        )
    }

    @concurrent
    func loadProject(
        pathWithNamespace: String,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabProject
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadResponse(
            GitLabProjectEndpoints.project(
                pathWithNamespace:
                    pathWithNamespace
            ),
            cachePolicy: .projects,
            refreshBehavior: refreshBehavior,
            onResponse: onResponse
        )
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
                    apiResponse: $0
                )
            )
        }
    }
}
