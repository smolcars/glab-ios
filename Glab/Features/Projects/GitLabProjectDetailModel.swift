typealias GitLabProjectDetailState =
    GitLabResourceDetailState<GitLabProject>

typealias GitLabProjectDetailModel =
    GitLabResourceDetailModel<
        GitLabProject,
        GitLabProjectRoute
    >

extension GitLabResourceDetailModel
where
    Resource == GitLabProject,
    Route == GitLabProjectRoute
{
    convenience init(
        route: GitLabProjectRoute,
        loader: any GitLabProjectResolving
    ) {
        self.init(
            route: route,
            initialResource:
                route.initialProject,
            loadResource: {
                (route: GitLabProjectRoute)
                    async throws(
                        GitLabSessionClientError
                    ) -> GitLabProject in
                try await loader.loadProject(
                    pathWithNamespace:
                        route.pathWithNamespace
                )
            },
            loadResourceEvents: {
                (
                    route: GitLabProjectRoute,
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onResponse:
                        @escaping @Sendable (
                            GitLabAPIResponseEvent<
                                GitLabProject
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader.loadProject(
                    pathWithNamespace:
                        route.pathWithNamespace,
                    refreshBehavior:
                        refreshBehavior,
                    onResponse: onResponse
                )
            }
        )
    }
}
