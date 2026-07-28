import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab search loader")
struct LiveGitLabSearchLoaderTests {
    @Test("Loads every scope and follows the exact next-page URL")
    func loadsScopePages() async throws {
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/search"
                        + "?scope=projects&search=glab&page=2"
            )
        )
        let client = RecordingSearchClient(
            nextPageURL: nextPageURL
        )
        let loader = LiveGitLabSearchLoader(
            client: client
        )

        let projects = try await loader.loadPage(
            scope: .projects,
            query: "glab",
            after: nil
        )
        let issues = try await loader.loadPage(
            scope: .issues,
            query: "glab",
            after: nil
        )
        let mergeRequests = try await loader.loadPage(
            scope: .mergeRequests,
            query: "glab",
            after: nil
        )
        let next = try await loader.loadPage(
            scope: .projects,
            query: "ignored for a next page",
            after: nextPageURL
        )

        #expect(projects.results.count == 1)
        #expect(issues.results.count == 1)
        #expect(mergeRequests.results.count == 1)
        #expect(next.results.count == 1)
        #expect(projects.nextPageURL == nextPageURL)
        #expect(
            await client.requests
                == [
                    "initial:projects:glab",
                    "initial:issues:glab",
                    "initial:merge_requests:glab",
                    "next:\(nextPageURL.absoluteString)",
                ]
        )
    }
}

private extension LiveGitLabSearchLoaderTests {
    actor RecordingSearchClient:
        GitLabPaginatedSessionRequestSending
    {
        let nextPageURL: URL
        private(set) var requests: [String] = []

        init(nextPageURL: URL) {
            self.nextPageURL = nextPageURL
        }

        func send<Response>(
            _ endpoint: GitLabAPIRequest<Response>
        ) async throws(GitLabSessionClientError)
            -> Response
        {
            throw .api(.invalidResponse)
        }

        func sendPage<Response>(
            _ page: GitLabAPIPageRequest<Response>
        ) async throws(GitLabSessionClientError)
            -> GitLabAPIResponse<Response>
        {
            switch page {
            case let .initial(endpoint):
                let query = Dictionary(
                    uniqueKeysWithValues:
                        endpoint.queryItems.map {
                            ($0.name, $0.value ?? "")
                        }
                )
                let scope = query["scope"] ?? "missing"
                requests.append(
                    "initial:\(scope):"
                        + (query["search"] ?? "missing")
                )

                let value:
                    [GitLabSearchResult]
                switch scope {
                case "projects":
                    value = [
                        .project(
                            GitLabProjectSearchResult(
                                id: 42,
                                name: "Glab iOS",
                                nameWithNamespace:
                                    "Mobile / Glab iOS",
                                pathWithNamespace:
                                    "mobile/glab-ios",
                                description: nil,
                                webURL: nil,
                                avatarURL: nil,
                                visibility: nil,
                                starCount: nil,
                                lastActivityAt: nil
                            )
                        ),
                    ]
                case "issues":
                    value = [
                        .issue(
                            GitLabIssueSearchResult(
                                id: 101,
                                iid: 7,
                                projectID: 42,
                                title: "Fix search",
                                description: nil,
                                state: "opened",
                                confidential: false,
                                labels: [],
                                author: nil,
                                updatedAt: nil,
                                webURL: nil
                            )
                        ),
                    ]
                case "merge_requests":
                    value = [
                        .mergeRequest(
                            GitLabMergeRequestSearchResult(
                                id: 201,
                                iid: 8,
                                projectID: 42,
                                title: "Add search",
                                description: nil,
                                state: "opened",
                                draft: false,
                                legacyWorkInProgress: nil,
                                labels: [],
                                author: nil,
                                updatedAt: nil,
                                webURL: nil
                            )
                        ),
                    ]
                default:
                    throw .api(.invalidResponse)
                }

                return GitLabAPIResponse(
                    value: value as! Response,
                    metadata: GitLabResponseMetadata(
                        nextPageURL: nextPageURL
                    )
                )
            case let .next(url):
                requests.append(
                    "next:\(url.absoluteString)"
                )
                let value:
                    [GitLabSearchResult] = [
                    .project(
                        GitLabProjectSearchResult(
                            id: 43,
                            name: "Glab macOS",
                            nameWithNamespace:
                                "Mobile / Glab macOS",
                            pathWithNamespace:
                                "mobile/glab-macos",
                            description: nil,
                            webURL: nil,
                            avatarURL: nil,
                            visibility: nil,
                            starCount: nil,
                            lastActivityAt: nil
                        )
                    ),
                ]
                return GitLabAPIResponse(
                    value: value as! Response,
                    metadata: GitLabResponseMetadata()
                )
            }
        }
    }
}
