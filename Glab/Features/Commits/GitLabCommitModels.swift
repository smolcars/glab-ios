import Foundation

typealias GitLabCommitsModel =
    GitLabPaginatedResourceModel<
        GitLabCommit,
        String
    >

extension GitLabPaginatedResourceModel
where
    Item == GitLabCommit,
    Identity == String
{
    convenience init(
        projectID: Int,
        refName: String?,
        loader: any GitLabCommitLoading
    ) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<
                    GitLabCommit
                > in
                let page =
                    try await loader
                    .loadCommitsPage(
                        projectID:
                            projectID,
                        refName: refName,
                        after: nextPageURL
                    )
                return GitLabResourcePage(
                    items: page.commits,
                    nextPageURL:
                        page.nextPageURL
                )
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @escaping @Sendable (
                            GitLabResourcePageEvent<
                                GitLabCommit
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader
                    .loadCommitsFirstPage(
                        projectID:
                            projectID,
                        refName: refName,
                        refreshBehavior:
                            refreshBehavior,
                        onPage: onPage
                    )
            },
            firstPageRefreshMode:
                .retainLoadedTail,
            identity: \.id,
            searchValues: {
                [
                    $0.title,
                    $0.message,
                    $0.authorName,
                    $0.shortID,
                ]
            }
        )
    }

    var commits: [GitLabCommit] {
        items
    }

    var displayedCommits: [GitLabCommit] {
        displayedItems
    }
}

typealias GitLabCommitDiffModel =
    GitLabResourceDetailModel<
        [GitLabDiffFile],
        GitLabCommitDiffRoute
    >

extension GitLabResourceDetailModel
where
    Resource == [GitLabDiffFile],
    Route == GitLabCommitDiffRoute
{
    convenience init(
        route: GitLabCommitDiffRoute,
        loader: any GitLabCommitLoading
    ) {
        self.init(
            route: route,
            loadResource: {
                (
                    route:
                        GitLabCommitDiffRoute
                ) async throws(
                    GitLabSessionClientError
                ) -> [GitLabDiffFile] in
                try await loader.loadCommitDiff(
                    at: route
                )
            },
            loadResourceEvents: {
                (
                    route:
                        GitLabCommitDiffRoute,
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onResponse:
                        @escaping @Sendable (
                            GitLabAPIResponseEvent<
                                [GitLabDiffFile]
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader
                    .loadCommitDiff(
                        at: route,
                        refreshBehavior:
                            refreshBehavior,
                        onResponse:
                            onResponse
                    )
            }
        )
    }
}
