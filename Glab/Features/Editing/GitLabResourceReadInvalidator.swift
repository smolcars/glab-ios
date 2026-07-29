import Foundation

nonisolated struct
    GitLabResourceReadInvalidator:
    Sendable
{
    private let client:
        any GitLabSessionRequestSending

    init(
        client:
            any GitLabSessionRequestSending
    ) {
        self.client = client
    }

    @concurrent
    func invalidateIssueReads(
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

    @concurrent
    func invalidateMergeRequestReads(
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

    @concurrent
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
