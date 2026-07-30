import Foundation

nonisolated protocol GitLabIssueCreationServing:
    Sendable
{
    func loadProject(
        projectID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabProject

    func loadProjectsPage(
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabProject>

    func loadProjectsFirstPage(
        search: String?,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabProject
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)

    func loadLabelsPage(
        projectID: Int,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectLabel
        >

    func loadLabelsFirstPage(
        projectID: Int,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabProjectLabel
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)

    func loadMembersPage(
        projectID: Int,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectMember
        >

    func loadMembersFirstPage(
        projectID: Int,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabProjectMember
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)

    func loadMilestones(
        projectID: Int
    ) async throws(GitLabSessionClientError)
        -> [GitLabIssueMilestone]

    func loadIterations(
        projectID: Int
    ) async throws(GitLabSessionClientError)
        -> [GitLabIssueIteration]

    func loadStatuses(
        projectPath: String
    ) async throws(GitLabSessionClientError)
        -> [GitLabIssueWorkItemStatus]

    func createIssue(
        _ input: GitLabIssueCreationInput
    ) async throws(GitLabSessionClientError)
        -> GitLabIssue

    func invalidateAffectedReads(
        projectID: Int
    ) async
}

extension GitLabIssueCreationServing {
    func loadMilestones(
        projectID: Int
    ) async throws(GitLabSessionClientError)
        -> [GitLabIssueMilestone]
    {
        []
    }

    func loadIterations(
        projectID: Int
    ) async throws(GitLabSessionClientError)
        -> [GitLabIssueIteration]
    {
        []
    }

    func loadStatuses(
        projectPath: String
    ) async throws(GitLabSessionClientError)
        -> [GitLabIssueWorkItemStatus]
    {
        []
    }
}

nonisolated struct LiveGitLabIssueCreationService:
    GitLabIssueCreationServing,
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
    func loadProject(
        projectID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabProject
    {
        try await client.send(
            GitLabProjectEndpoints.project(
                pathWithNamespace:
                    String(projectID)
            )
        )
    }

    @concurrent
    func loadProjectsPage(
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabProject>
    {
        try await loadPage(
            initial:
                GitLabProjectEndpoints
                .issueCreationProjects(
                    search: search
                ),
            after: nextPageURL
        )
    }

    @concurrent
    func loadProjectsFirstPage(
        search: String?,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabProject
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await loadFirstPage(
            GitLabProjectEndpoints
                .issueCreationProjects(
                    search: search
                ),
            refreshBehavior:
                refreshBehavior,
            onPage: onPage
        )
    }

    @concurrent
    func loadLabelsPage(
        projectID: Int,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectLabel
        >
    {
        try await loadPage(
            initial:
                GitLabIssueCreationEndpoints
                .labels(projectID: projectID),
            after: nextPageURL
        )
    }

    @concurrent
    func loadLabelsFirstPage(
        projectID: Int,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabProjectLabel
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await loadFirstPage(
            GitLabIssueCreationEndpoints
                .labels(projectID: projectID),
            refreshBehavior:
                refreshBehavior,
            onPage: onPage
        )
    }

    @concurrent
    func loadMembersPage(
        projectID: Int,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectMember
        >
    {
        try await loadPage(
            initial:
                GitLabProjectMemberEndpoints
                .members(projectID: projectID),
            after: nextPageURL
        )
    }

    @concurrent
    func loadMembersFirstPage(
        projectID: Int,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabProjectMember
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await loadFirstPage(
            GitLabProjectMemberEndpoints
                .members(projectID: projectID),
            refreshBehavior:
                refreshBehavior,
            onPage: onPage
        )
    }

    @concurrent
    func loadMilestones(
        projectID: Int
    ) async throws(GitLabSessionClientError)
        -> [GitLabIssueMilestone]
    {
        try await client.send(
            GitLabIssueCreationEndpoints
                .milestones(
                    projectID: projectID
                )
        )
    }

    @concurrent
    func loadIterations(
        projectID: Int
    ) async throws(GitLabSessionClientError)
        -> [GitLabIssueIteration]
    {
        do {
            return try await client.send(
                GitLabIssueCreationEndpoints
                    .iterations(
                        projectID: projectID
                    )
            )
        } catch
            .api(.forbidden),
            .api(.notFound)
        {
            return []
        }
    }

    @concurrent
    func loadStatuses(
        projectPath: String
    ) async throws(GitLabSessionClientError)
        -> [GitLabIssueWorkItemStatus]
    {
        let endpoint:
            GitLabAPIRequest<
                GitLabIssueCreationStatusGraphQLResponse
            >
        do {
            endpoint =
                try GitLabIssueCreationEndpoints
                    .statuses(
                        projectPath:
                            projectPath
                    )
        } catch {
            throw .api(.invalidResponse)
        }
        let response =
            try await client.send(endpoint)
        return response.validatedStatuses(
            projectPath: projectPath
        )
            ?? []
    }

    @concurrent
    func createIssue(
        _ input: GitLabIssueCreationInput
    ) async throws(GitLabSessionClientError)
        -> GitLabIssue
    {
        do {
            if
                input.status != nil
                    || input.iteration != nil
            {
                let endpoint:
                    GitLabAPIRequest<
                        GitLabIssueCreateGraphQLResponse
                    >
                do {
                    endpoint =
                        try GitLabIssueEndpoints
                            .createWithWorkItemFields(
                                input
                            )
                } catch {
                    throw GitLabSessionClientError
                        .api(.invalidResponse)
                }
                let response =
                    try await client.send(
                        endpoint
                    )
                guard
                    let route =
                        response
                        .validatedRoute(
                            projectID:
                                input.projectID
                        )
                else {
                    throw GitLabSessionClientError
                        .api(.invalidResponse)
                }
                return try await client.send(
                    GitLabIssueEndpoints
                        .issue(at: route)
                )
            }

            let endpoint:
                GitLabAPIRequest<GitLabIssue>
            do {
                endpoint =
                    try GitLabIssueEndpoints
                        .create(input)
            } catch {
                throw GitLabSessionClientError
                    .api(.invalidResponse)
            }
            return try await client.send(endpoint)
        } catch {
            let sessionError =
                error
                    as? GitLabSessionClientError
                ?? .api(.transport)
            if
                sessionError
                    .mutationDeliveryCertainty
                    == .deliveryUnknown
            {
                await invalidateAffectedReads(
                    projectID:
                        input.projectID
                )
            }
            throw sessionError
        }
    }

    @concurrent
    func invalidateAffectedReads(
        projectID: Int
    ) async {
        for mode in GitLabIssueListMode.allCases {
            await client.invalidateCachedResponse(
                GitLabIssueEndpoints
                    .issues(for: mode)
            )
        }
        for endpoint in [
            HomeDashboardEndpoints
                .assignedIssues,
            HomeDashboardEndpoints
                .createdIssues,
        ] {
            await client
                .invalidateCachedResponse(
                    endpoint
                )
        }
        await client.invalidateCachedResponse(
            GitLabProjectEndpoints
                .projects(for: .recent)
        )
        await client.invalidateCachedResponse(
            HomeDashboardEndpoints
                .recentProjects
        )
        await client.invalidateCachedResponse(
            GitLabIssueEndpoints
                .projectIssues(
                    projectID: projectID,
                    state: .opened
                )
        )
    }

    private func loadPage<Item>(
        initial:
            GitLabAPIRequest<[Item]>,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<Item>
    where
        Item: Decodable & Sendable
    {
        let request:
            GitLabAPIPageRequest<[Item]> =
                if let nextPageURL {
                    .next(nextPageURL)
                } else {
                    .initial(initial)
                }
        let response = try await client
            .sendPage(request)
        return GitLabResourcePage(
            items: response.value,
            nextPageURL:
                response.metadata.nextPageURL,
            totalCount:
                response.metadata.totalCount
        )
    }

    private func loadFirstPage<Item>(
        _ request:
            GitLabAPIRequest<[Item]>,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<Item>
            ) async -> Void
    ) async throws(GitLabSessionClientError)
    where
        Item: Decodable & Sendable
    {
        try await client.loadPage(
            .initial(request),
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
