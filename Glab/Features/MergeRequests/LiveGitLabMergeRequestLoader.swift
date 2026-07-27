import Foundation

nonisolated protocol GitLabMergeRequestLoading: Sendable {
    func loadMergeRequestsPage(
        for mode: GitLabMergeRequestListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestPage

    func loadMergeRequest(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequest
}

nonisolated struct LiveGitLabMergeRequestLoader:
    GitLabMergeRequestLoading,
    Sendable
{
    private let client:
        any GitLabPaginatedSessionRequestSending

    init(
        client: any GitLabPaginatedSessionRequestSending
    ) {
        self.client = client
    }

    @concurrent
    func loadMergeRequestsPage(
        for mode: GitLabMergeRequestListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestPage
    {
        let request: GitLabAPIPageRequest<
            [GitLabMergeRequest]
        > =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(
                    GitLabMergeRequestEndpoints
                        .mergeRequests(for: mode)
                )
            }
        let response = try await client.sendPage(request)

        return GitLabMergeRequestPage(
            mergeRequests: response.value,
            nextPageURL: response.metadata.nextPageURL
        )
    }

    @concurrent
    func loadMergeRequest(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequest
    {
        try await client.send(
            GitLabMergeRequestEndpoints.mergeRequest(
                at: route
            )
        )
    }
}
