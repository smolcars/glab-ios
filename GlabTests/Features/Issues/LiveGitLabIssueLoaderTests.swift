import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab issue loader")
struct LiveGitLabIssueLoaderTests {
    @Test("Loads the initial page, next page, and issue detail")
    func loadsIssueResources() async throws {
        let issue = makeTestIssue()
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/issues?page=2"
            )
        )
        let client = RecordingIssueClient(
            issue: issue,
            returnedNextPageURL: nextPageURL
        )
        let loader = LiveGitLabIssueLoader(client: client)

        let initialPage = try await loader.loadAssignedIssuesPage(
            after: nil
        )
        let nextPage = try await loader.loadAssignedIssuesPage(
            after: nextPageURL
        )
        let detail = try await loader.loadIssue(at: issue.route)

        #expect(initialPage.issues == [issue])
        #expect(initialPage.nextPageURL == nextPageURL)
        #expect(nextPage.issues == [issue])
        #expect(detail == issue)
        #expect(
            await client.pageSources
                == [
                    "initial:issues",
                    "next:\(nextPageURL.absoluteString)",
                ]
        )
        #expect(
            await client.detailPaths
                == [["projects", "42", "issues", "7"]]
        )
    }
}

private extension LiveGitLabIssueLoaderTests {
    actor RecordingIssueClient:
        GitLabPaginatedSessionRequestSending
    {
        let issue: GitLabIssue
        let returnedNextPageURL: URL?
        private(set) var pageSources: [String] = []
        private(set) var detailPaths: [[String]] = []

        init(
            issue: GitLabIssue,
            returnedNextPageURL: URL?
        ) {
            self.issue = issue
            self.returnedNextPageURL = returnedNextPageURL
        }

        func send<Response>(
            _ endpoint: GitLabAPIRequest<Response>
        ) async throws(GitLabSessionClientError) -> Response {
            detailPaths.append(endpoint.pathComponents)
            return issue as! Response
        }

        func sendPage<Response>(
            _ page: GitLabAPIPageRequest<Response>
        ) async throws(GitLabSessionClientError)
            -> GitLabAPIResponse<Response>
        {
            switch page {
            case let .initial(endpoint):
                pageSources.append(
                    "initial:\(endpoint.pathComponents.joined(separator: "/"))"
                )
            case let .next(url):
                pageSources.append("next:\(url.absoluteString)")
            }

            return GitLabAPIResponse(
                value: [issue] as! Response,
                metadata: GitLabResponseMetadata(
                    nextPageURL: returnedNextPageURL
                )
            )
        }
    }
}

