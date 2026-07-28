import Foundation

nonisolated struct LiveGitLabResourceEditService:
    GitLabResourceEditing,
    Sendable
{
    private let client:
        any GitLabSessionRequestSending

    init(
        client: any GitLabSessionRequestSending
    ) {
        self.client = client
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
            await invalidateIssueReads(
                route: route
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
            await invalidateMergeRequestReads(
                route: route
            )
            return .mergeRequest(
                mergeRequest
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
}
