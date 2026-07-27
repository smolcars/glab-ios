import Foundation

nonisolated protocol GitLabIssueLoading: Sendable {
    func loadAssignedIssuesPage(
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError) -> GitLabIssuePage

    func loadIssue(
        at route: GitLabIssueRoute
    ) async throws(GitLabSessionClientError) -> GitLabIssue
}

nonisolated struct LiveGitLabIssueLoader:
    GitLabIssueLoading,
    Sendable
{
    private let client: any GitLabPaginatedSessionRequestSending

    init(client: any GitLabPaginatedSessionRequestSending) {
        self.client = client
    }

    @concurrent
    func loadAssignedIssuesPage(
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError) -> GitLabIssuePage {
        let request: GitLabAPIPageRequest<[GitLabIssue]> =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(GitLabIssueEndpoints.assignedIssues)
            }
        let response = try await client.sendPage(request)

        return GitLabIssuePage(
            issues: response.value,
            nextPageURL: response.metadata.nextPageURL
        )
    }

    @concurrent
    func loadIssue(
        at route: GitLabIssueRoute
    ) async throws(GitLabSessionClientError) -> GitLabIssue {
        try await client.send(
            GitLabIssueEndpoints.issue(at: route)
        )
    }
}

