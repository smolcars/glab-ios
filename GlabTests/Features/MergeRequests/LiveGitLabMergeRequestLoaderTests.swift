import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab merge request loader")
struct LiveGitLabMergeRequestLoaderTests {
    @Test("Loads both list modes, a next page, and detail")
    func loadsMergeRequestResources() async throws {
        let mergeRequest = makeTestMergeRequest()
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "merge_requests?page=2"
            )
        )
        let client = RecordingMergeRequestClient(
            mergeRequest: mergeRequest,
            returnedNextPageURL: nextPageURL
        )
        let loader = LiveGitLabMergeRequestLoader(
            client: client
        )

        let assigned = try await loader.loadMergeRequestsPage(
            for: .assigned,
            after: nil
        )
        let reviewRequested = try await loader.loadMergeRequestsPage(
            for: .reviewRequested,
            after: nil
        )
        let nextPage = try await loader.loadMergeRequestsPage(
            for: .assigned,
            after: nextPageURL
        )
        let detail = try await loader.loadMergeRequest(
            at: mergeRequest.route
        )

        #expect(assigned.mergeRequests == [mergeRequest])
        #expect(assigned.nextPageURL == nextPageURL)
        #expect(reviewRequested.mergeRequests == [mergeRequest])
        #expect(nextPage.mergeRequests == [mergeRequest])
        #expect(detail == mergeRequest)
        #expect(
            await client.pageSources
                == [
                    "initial:merge_requests:assigned_to_me",
                    "initial:merge_requests:reviews_for_me",
                    "next:\(nextPageURL.absoluteString)",
                ]
        )
        #expect(
            await client.detailPaths
                == [["projects", "42", "merge_requests", "7"]]
        )
    }
}

private extension LiveGitLabMergeRequestLoaderTests {
    actor RecordingMergeRequestClient:
        GitLabPaginatedSessionRequestSending
    {
        let mergeRequest: GitLabMergeRequest
        let returnedNextPageURL: URL?
        private(set) var pageSources: [String] = []
        private(set) var detailPaths: [[String]] = []

        init(
            mergeRequest: GitLabMergeRequest,
            returnedNextPageURL: URL?
        ) {
            self.mergeRequest = mergeRequest
            self.returnedNextPageURL = returnedNextPageURL
        }

        func send<Response>(
            _ endpoint: GitLabAPIRequest<Response>
        ) async throws(GitLabSessionClientError) -> Response {
            detailPaths.append(endpoint.pathComponents)
            return mergeRequest as! Response
        }

        func sendPage<Response>(
            _ page: GitLabAPIPageRequest<Response>
        ) async throws(GitLabSessionClientError)
            -> GitLabAPIResponse<Response>
        {
            switch page {
            case let .initial(endpoint):
                let scope = endpoint.queryItems.first {
                    $0.name == "scope"
                }?.value ?? "missing"
                pageSources.append(
                    "initial:"
                        + endpoint.pathComponents.joined(separator: "/")
                        + ":\(scope)"
                )
            case let .next(url):
                pageSources.append("next:\(url.absoluteString)")
            }

            return GitLabAPIResponse(
                value: [mergeRequest] as! Response,
                metadata: GitLabResponseMetadata(
                    nextPageURL: returnedNextPageURL
                )
            )
        }
    }
}
