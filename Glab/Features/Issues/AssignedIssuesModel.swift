import Foundation

typealias AssignedIssuesModel =
    GitLabPaginatedResourceModel<
        GitLabIssue,
        GitLabIssueRoute
    >

extension GitLabPaginatedResourceModel
where
    Item == GitLabIssue,
    Identity == GitLabIssueRoute
{
    convenience init(loader: any GitLabIssueLoading) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<GitLabIssue> in
                let page = try await loader
                    .loadAssignedIssuesPage(
                        after: nextPageURL
                    )
                return GitLabResourcePage(
                    items: page.issues,
                    nextPageURL: page.nextPageURL
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

    var issues: [GitLabIssue] {
        items
    }

    var displayedIssues: [GitLabIssue] {
        displayedItems
    }
}
