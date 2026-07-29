import Foundation

typealias IssuesModel =
    GitLabPaginatedResourceModel<
        GitLabIssue,
        GitLabIssueRoute
    >

typealias AssignedIssuesModel = IssuesModel

extension GitLabPaginatedResourceModel
where
    Item == GitLabIssue,
    Identity == GitLabIssueRoute
{
    convenience init(
        mode: GitLabIssueListMode,
        loader: any GitLabIssueLoading
    ) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<GitLabIssue> in
                let page = try await loader
                    .loadIssuesPage(
                        for: mode,
                        after: nextPageURL
                    )
                return GitLabResourcePage(
                    items: page.issues,
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
                                GitLabIssue
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader
                    .loadIssuesFirstPage(
                        for: mode,
                        refreshBehavior:
                            refreshBehavior,
                        onPage: onPage
                    )
            },
            identity: { $0.route },
            searchValues: {
                [
                    $0.title,
                    $0.references.full,
                ]
                    + $0.labels
                    + $0.assignees.flatMap {
                        [$0.name, $0.username]
                    }
            }
        )
    }

    convenience init(
        loader: any GitLabIssueLoading
    ) {
        self.init(
            mode: .assigned,
            loader: loader
        )
    }

    var issues: [GitLabIssue] {
        items
    }

    var displayedIssues: [GitLabIssue] {
        displayedItems
    }

    @discardableResult
    func reconcileAssignedIssue(
        _ issue: GitLabIssue,
        currentUserID: Int
    ) -> Bool {
        if issue.isAssignedOpenWork(
            for: currentUserID
        ) {
            return reconcileItemIfPresent(
                issue
            )
        }
        return removeItemIfPresent(issue)
    }

    @discardableResult
    func reconcileIssue(
        _ issue: GitLabIssue,
        mode: GitLabIssueListMode,
        currentUserID: Int
    ) -> Bool {
        if issue.isOpenWork(
            for: mode,
            userID: currentUserID
        ) {
            return reconcileItemIfPresent(
                issue
            )
        }
        return removeItemIfPresent(issue)
    }
}

extension GitLabIssue {
    func isAssignedOpenWork(
        for userID: Int
    ) -> Bool {
        stateKind == .opened
            && assignees.contains {
                $0.id == userID
            }
    }

    func isOpenWork(
        for mode: GitLabIssueListMode,
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
        case .created:
            return author.id == userID
        }
    }
}
