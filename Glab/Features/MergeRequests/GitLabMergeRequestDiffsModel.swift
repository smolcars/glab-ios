import Foundation

typealias GitLabMergeRequestDiffsModel =
    GitLabPaginatedResourceModel<
        GitLabMergeRequestDiffFile,
        GitLabMergeRequestDiffFileID
    >

extension GitLabPaginatedResourceModel
where
    Item == GitLabMergeRequestDiffFile,
    Identity == GitLabMergeRequestDiffFileID
{
    convenience init(
        route: GitLabMergeRequestRoute,
        headSHA: String,
        loader: any GitLabMergeRequestDiffLoading
    ) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<
                    GitLabMergeRequestDiffFile
                > in
                let page = try await loader
                    .loadMergeRequestDiffsPage(
                        at: route,
                        headSHA: headSHA,
                        after: nextPageURL
                    )
                return GitLabResourcePage(
                    items: page.files,
                    nextPageURL: page.nextPageURL,
                    totalCount: page.totalCount
                )
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @escaping @Sendable (
                            GitLabResourcePageEvent<
                                GitLabMergeRequestDiffFile
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader
                    .loadMergeRequestDiffsFirstPage(
                        at: route,
                        headSHA: headSHA,
                        refreshBehavior:
                            refreshBehavior,
                        onPage: onPage
                    )
            },
            identity: \.id,
            searchValues: {
                [$0.oldPath, $0.newPath]
            }
        )
    }

    var files: [GitLabMergeRequestDiffFile] {
        items
    }

    var displayedFiles: [GitLabMergeRequestDiffFile] {
        displayedItems
    }
}
