import Foundation

nonisolated protocol GitLabSearchLoading:
    Sendable
{
    func loadPage(
        scope: GitLabSearchScope,
        query: String,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabSearchPage
}

nonisolated struct LiveGitLabSearchLoader:
    GitLabSearchLoading,
    Sendable
{
    private let client:
        any GitLabPaginatedSessionRequestSending

    init(
        client:
            any GitLabPaginatedSessionRequestSending
    ) {
        self.client = client
    }

    @concurrent
    func loadPage(
        scope: GitLabSearchScope,
        query: String,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabSearchPage
    {
        let request:
            GitLabAPIPageRequest<
                [GitLabSearchResult]
            > =
                if let nextPageURL {
                    .next(nextPageURL)
                } else {
                    .initial(
                        GitLabSearchEndpoints.search(
                            scope: scope,
                            query: query
                        )
                    )
                }
        let response = try await client.sendPage(
            request
        )
        guard
            response.value.allSatisfy({
                $0.scope == scope
            })
        else {
            throw .api(.invalidResponse)
        }

        return GitLabSearchPage(
            results: response.value,
            nextPageURL:
                response.metadata.nextPageURL,
            totalCount:
                response.metadata.totalCount
        )
    }
}
