typealias GitLabMergeRequestDetailState =
    GitLabResourceDetailState<GitLabMergeRequest>

typealias GitLabMergeRequestDetailModel =
    GitLabResourceDetailModel<
        GitLabMergeRequest,
        GitLabMergeRequestRoute
    >

typealias GitLabMergeRequestApprovalModel =
    GitLabResourceDetailModel<
        GitLabMergeRequestApprovalAvailability,
        GitLabMergeRequestRoute
    >

typealias GitLabMergeRequestApprovalDetailsModel =
    GitLabResourceDetailModel<
        GitLabMergeRequestApprovalDetailsAvailability,
        GitLabMergeRequestRoute
    >

typealias GitLabMergeRequestDiffSummaryModel =
    GitLabResourceDetailModel<
        GitLabMergeRequestDiffSummaryAvailability,
        Int
    >

extension GitLabResourceDetailModel
where
    Resource == GitLabMergeRequest,
    Route == GitLabMergeRequestRoute
{
    convenience init(
        route: GitLabMergeRequestRoute,
        loader: any GitLabMergeRequestLoading
    ) {
        self.init(
            route: route,
            loadResource: {
                (route: GitLabMergeRequestRoute) async throws(
                    GitLabSessionClientError
                ) -> GitLabMergeRequest in
                try await loader.loadMergeRequest(at: route)
            },
            loadResourceEvents: {
                (
                    route:
                        GitLabMergeRequestRoute,
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onResponse:
                        @escaping @Sendable (
                            GitLabAPIResponseEvent<
                                GitLabMergeRequest
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader.loadMergeRequest(
                    at: route,
                    refreshBehavior: refreshBehavior,
                    onResponse: onResponse
                )
            }
        )
    }
}

extension GitLabResourceDetailModel
where
    Resource
        == GitLabMergeRequestDiffSummaryAvailability,
    Route == Int
{
    convenience init(
        mergeRequestID: Int,
        loader:
            any GitLabMergeRequestDiffSummaryLoading
    ) {
        self.init(
            route: mergeRequestID,
            loadResource: {
                (mergeRequestID: Int) async throws(
                    GitLabSessionClientError
                )
                    -> GitLabMergeRequestDiffSummaryAvailability
                in
                try await loader
                    .loadMergeRequestDiffSummary(
                        mergeRequestID:
                            mergeRequestID
                    )
            }
        )
    }
}

extension GitLabResourceDetailModel
where
    Resource
        == GitLabMergeRequestApprovalAvailability,
    Route == GitLabMergeRequestRoute
{
    convenience init(
        route: GitLabMergeRequestRoute,
        loader:
            any GitLabMergeRequestApprovalLoading
    ) {
        self.init(
            route: route,
            loadResource: {
                (route: GitLabMergeRequestRoute) async throws(
                    GitLabSessionClientError
                )
                    -> GitLabMergeRequestApprovalAvailability
                in
                try await loader
                    .loadMergeRequestApproval(
                        at: route
                    )
            },
            loadResourceEvents: {
                (
                    route:
                        GitLabMergeRequestRoute,
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onResponse:
                        @escaping @Sendable (
                            GitLabAPIResponseEvent<
                                GitLabMergeRequestApprovalAvailability
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader
                    .loadMergeRequestApproval(
                        at: route,
                        refreshBehavior:
                            refreshBehavior,
                        onResponse: onResponse
                    )
            }
        )
    }
}
