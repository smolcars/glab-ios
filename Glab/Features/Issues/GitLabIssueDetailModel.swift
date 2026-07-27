typealias GitLabIssueDetailState =
    GitLabResourceDetailState<GitLabIssue>

typealias GitLabIssueDetailModel =
    GitLabResourceDetailModel<
        GitLabIssue,
        GitLabIssueRoute
    >

extension GitLabResourceDetailModel
where
    Resource == GitLabIssue,
    Route == GitLabIssueRoute
{
    convenience init(
        route: GitLabIssueRoute,
        loader: any GitLabIssueLoading
    ) {
        self.init(
            route: route,
            loadResource: {
                (route: GitLabIssueRoute) async throws(
                    GitLabSessionClientError
                ) -> GitLabIssue in
                try await loader.loadIssue(at: route)
            }
        )
    }
}
