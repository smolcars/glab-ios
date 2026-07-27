import Foundation
import Testing
@testable import Glab

@Suite("GitLab paginated resource model")
struct GitLabPaginatedResourceModelTests {
    @Test(
        "Preserves loaded content across recovery categories",
        arguments: [
            GitLabSessionClientError.api(
                .connectivity(.notConnectedToInternet)
            ),
            GitLabSessionClientError.api(
                .connectivity(.timedOut)
            ),
            GitLabSessionClientError.api(
                .server(statusCode: 503)
            ),
            GitLabSessionClientError.api(.forbidden),
            GitLabSessionClientError.api(.unauthenticated),
            GitLabSessionClientError.api(
                .rateLimited(retryAfterSeconds: 30)
            ),
            GitLabSessionClientError.refresh(
                .token(.invalidGrant)
            ),
        ]
    )
    @MainActor
    func preservesContent(
        error: GitLabSessionClientError
    ) async {
        let loader = FailingRefreshLoader(error: error)
        let model = GitLabPaginatedResourceModel<Int, Int>(
            loadPage: {
                (pageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                try await loader.load(pageURL)
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )

        await model.loadIfNeeded()
        await model.refresh()

        #expect(model.items == [7])
        #expect(model.loadError == error)
        #expect(model.didFailRefresh)
        #expect(model.hasLoaded)
        #expect(model.reliableItemCount == nil)
    }
}

private actor FailingRefreshLoader {
    private let error: GitLabSessionClientError
    private var requestCount = 0

    init(error: GitLabSessionClientError) {
        self.error = error
    }

    func load(
        _ pageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<Int>
    {
        requestCount += 1

        if requestCount == 1 {
            return GitLabResourcePage(
                items: [7],
                nextPageURL: nil,
                totalCount: 1
            )
        }

        throw error
    }
}
