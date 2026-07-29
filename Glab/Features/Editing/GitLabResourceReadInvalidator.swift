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
        for state in GitLabProjectIssueState.allCases {
            await client.invalidateCachedResponse(
                GitLabIssueEndpoints
                    .projectIssues(
                        projectID:
                            route.projectID,
                        state: state
                    )
            )
        }
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
        for mode
            in GitLabMergeRequestListMode
                .allCases
        {
            await client.invalidateCachedResponse(
                GitLabMergeRequestEndpoints
                    .mergeRequests(for: mode)
            )
        }
        for endpoint in [
            HomeDashboardEndpoints
                .assignedMergeRequests,
            HomeDashboardEndpoints
                .createdMergeRequests,
            HomeDashboardEndpoints
                .reviewRequests,
        ] {
            await client
                .invalidateCachedResponse(
                    endpoint
                )
        }
        for state
            in GitLabProjectMergeRequestState
                .allCases
        {
            await client.invalidateCachedResponse(
                GitLabMergeRequestEndpoints
                    .projectMergeRequests(
                        projectID:
                            route.projectID,
                        state: state
                    )
            )
        }
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
