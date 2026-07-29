import Foundation

typealias MergeRequestsModel =
    GitLabPaginatedResourceModel<
        GitLabMergeRequest,
        GitLabMergeRequestRoute
    >

extension GitLabPaginatedResourceModel
where
    Item == GitLabMergeRequest,
    Identity == GitLabMergeRequestRoute
{
    convenience init(
        mode: GitLabMergeRequestListMode,
        loader: any GitLabMergeRequestLoading
    ) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<
                    GitLabMergeRequest
                > in
                let page = try await loader
                    .loadMergeRequestsPage(
                        for: mode,
                        after: nextPageURL
                    )
                return GitLabResourcePage(
                    items: page.mergeRequests,
                    nextPageURL: page.nextPageURL
                )
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @escaping @Sendable (
                            GitLabResourcePageEvent<
                                GitLabMergeRequest
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader
                    .loadMergeRequestsFirstPage(
                        for: mode,
                        refreshBehavior:
                            refreshBehavior,
                        onPage: onPage
                    )
            },
            identity: { $0.route },
            searchValues: {
                let users =
                    [$0.author]
                    + $0.assignees
                    + $0.reviewers
                return [
                    $0.title,
                    $0.references.full,
                    $0.sourceBranch,
                    $0.targetBranch,
                ]
                    + $0.labels
                    + users.flatMap {
                        [$0.name, $0.username]
                    }
            }
        )
    }

    var mergeRequests: [GitLabMergeRequest] {
        items
    }

    var displayedMergeRequests: [GitLabMergeRequest] {
        displayedItems
    }

    @discardableResult
    func reconcileMergeRequest(
        _ mergeRequest: GitLabMergeRequest,
        mode: GitLabMergeRequestListMode,
        currentUserID: Int
    ) -> Bool {
        if mergeRequest.isOpenWork(
            for: mode,
            userID: currentUserID
        ) {
            return reconcileItemIfPresent(
                mergeRequest
            )
        }
        return removeItemIfPresent(
            mergeRequest
        )
    }
}

extension GitLabMergeRequest {
    func isOpenWork(
        for mode:
            GitLabMergeRequestListMode,
        userID: Int
    ) -> Bool {
        guard stateKind == .opened else {
            return false
        }
        switch mode {
        case .assigned:
            return assignees.contains {
                $0.id == userID
            }
        case .reviewRequested:
            return reviewers.contains {
                $0.id == userID
            }
        }
    }
}
