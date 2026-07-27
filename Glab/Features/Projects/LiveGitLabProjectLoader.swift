import Foundation

nonisolated protocol GitLabProjectLoading: Sendable {
    func loadProjectsPage(
        for mode: GitLabProjectListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabProjectPage
}

nonisolated struct LiveGitLabProjectLoader:
    GitLabProjectLoading,
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
    func loadProjectsPage(
        for mode: GitLabProjectListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabProjectPage
    {
        let request: GitLabAPIPageRequest<[GitLabProject]> =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(
                    GitLabProjectEndpoints.projects(
                        for: mode
                    )
                )
            }
        let response = try await client.sendPage(request)

        return GitLabProjectPage(
            projects: response.value,
            nextPageURL: response.metadata.nextPageURL
        )
    }
}

