import Foundation

nonisolated struct LiveGitLabResourceEditService:
    GitLabResourceEditing,
    Sendable
{
    private let client:
        any GitLabSessionRequestSending
    private let paginatedClient:
        (any GitLabPaginatedSessionRequestSending)?

    init(
        client: any GitLabSessionRequestSending
    ) {
        self.client = client
        paginatedClient =
            client as?
                any GitLabPaginatedSessionRequestSending
    }

    @concurrent
    func loadLatest(
        _ target: GitLabResourceEditTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        switch target {
        case let .issue(route):
            let issue = try await client.send(
                GitLabIssueEndpoints.issue(
                    at: route
                )
            )
            return .issue(issue)
        case let .mergeRequest(route):
            let mergeRequest =
                try await client.send(
                    GitLabMergeRequestEndpoints
                        .mergeRequest(at: route)
                )
            return .mergeRequest(
                mergeRequest
            )
        }
    }

    @concurrent
    func update(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceEditChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        switch target {
        case let .issue(route):
            let endpoint:
                GitLabAPIRequest<GitLabIssue>
            do {
                endpoint =
                    try GitLabIssueEndpoints
                        .update(
                            at: route,
                            changes: changes
                        )
            } catch {
                throw .api(.invalidResponse)
            }
            let issue = try await client.send(
                endpoint
            )
            return .issue(issue)

        case let .mergeRequest(route):
            let endpoint:
                GitLabAPIRequest<
                    GitLabMergeRequest
                >
            do {
                endpoint =
                    try GitLabMergeRequestEndpoints
                        .update(
                            at: route,
                            changes: changes
                        )
            } catch {
                throw .api(.invalidResponse)
            }
            let mergeRequest =
                try await client.send(
                    endpoint
                )
            return .mergeRequest(
                mergeRequest
            )
        }
    }

    @concurrent
    func loadLabelsPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectLabel
        >
    {
        try await loadMetadataPage(
            initial:
                GitLabIssueCreationEndpoints
                .labels(
                    projectID: projectID,
                    search: search
                ),
            after: nextPageURL
        )
    }

    @concurrent
    func loadMembersPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectMember
        >
    {
        try await loadMetadataPage(
            initial:
                GitLabIssueCreationEndpoints
                .members(
                    projectID: projectID,
                    search: search
                ),
            after: nextPageURL
        )
    }

    @concurrent
    func updateMetadata(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceMetadataChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        switch target {
        case let .issue(route):
            let endpoint:
                GitLabAPIRequest<GitLabIssue>
            do {
                endpoint =
                    try GitLabIssueEndpoints
                        .updateMetadata(
                            at: route,
                            changes: changes
                        )
            } catch {
                throw .api(.invalidResponse)
            }
            let issue = try await client.send(
                endpoint
            )
            return .issue(issue)

        case let .mergeRequest(route):
            let endpoint:
                GitLabAPIRequest<
                    GitLabMergeRequest
                >
            do {
                endpoint =
                    try GitLabMergeRequestEndpoints
                        .updateMetadata(
                            at: route,
                            changes: changes
                        )
            } catch {
                throw .api(.invalidResponse)
            }
            let mergeRequest =
                try await client.send(
                    endpoint
                )
            return .mergeRequest(
                mergeRequest
            )
        }
    }

    @concurrent
    func invalidateAffectedReads(
        for target: GitLabResourceEditTarget
    ) async {
        switch target {
        case let .issue(route):
            await invalidateIssueReads(
                route: route
            )
        case let .mergeRequest(route):
            await invalidateMergeRequestReads(
                route: route
            )
        }
    }

    private func invalidateIssueReads(
        route: GitLabIssueRoute
    ) async {
        await client.invalidateCachedResponse(
            GitLabIssueEndpoints.issue(
                at: route
            )
        )
        await client.invalidateCachedResponse(
            GitLabIssueEndpoints.assignedIssues
        )
        await client.invalidateCachedResponse(
            HomeDashboardEndpoints
                .assignedIssues
        )
        await invalidateTodoReads()
    }

    private func invalidateMergeRequestReads(
        route: GitLabMergeRequestRoute
    ) async {
        await client.invalidateCachedResponse(
            GitLabMergeRequestEndpoints
                .mergeRequest(at: route)
        )
        await client.invalidateCachedResponse(
            GitLabMergeRequestEndpoints
                .mergeRequests(for: .assigned)
        )
        await client.invalidateCachedResponse(
            GitLabMergeRequestEndpoints
                .mergeRequests(
                    for: .reviewRequested
                )
        )
        await client.invalidateCachedResponse(
            HomeDashboardEndpoints
                .assignedMergeRequests
        )
        await client.invalidateCachedResponse(
            HomeDashboardEndpoints
                .reviewRequests
        )
        await invalidateTodoReads()
    }

    private func invalidateTodoReads() async {
        for state in GitLabTodoState.allCases {
            for targetFilter
                in GitLabTodoTargetFilter.allCases
            {
                await client
                    .invalidateCachedResponse(
                        GitLabTodoEndpoints.todos(
                            state: state,
                            targetFilter:
                                targetFilter
                        )
                    )
            }
        }
    }

    private func loadMetadataPage<Item>(
        initial:
            GitLabAPIRequest<[Item]>,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<Item>
    where
        Item: Decodable & Sendable
    {
        guard let paginatedClient else {
            throw .api(.invalidResponse)
        }
        let request:
            GitLabAPIPageRequest<[Item]> =
                if let nextPageURL {
                    .next(nextPageURL)
                } else {
                    .initial(initial)
                }
        let response =
            try await paginatedClient
                .sendPage(request)
        return GitLabResourcePage(
            items: response.value,
            nextPageURL:
                response.metadata.nextPageURL,
            totalCount:
                response.metadata.totalCount
        )
    }
}
