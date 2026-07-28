typealias GitLabMergeRequestDetailState =
    GitLabResourceDetailState<GitLabMergeRequest>

typealias GitLabMergeRequestDetailModel =
    GitLabResourceDetailModel<
        GitLabMergeRequest,
        GitLabMergeRequestRoute
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
