import Foundation
import Testing
@testable import Glab

@Suite("GitLab discussion endpoints")
struct GitLabDiscussionEndpointTests {
    @Test("Builds the issue discussions endpoint")
    func buildsIssueEndpoint() {
        let endpoint = GitLabDiscussionEndpoints.discussions(
            for: .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )
        )

        #expect(endpoint.method == .get)
        #expect(endpoint.requiredAccess == .read)
        #expect(
            endpoint.pathComponents
                == [
                    "projects",
                    "42",
                    "issues",
                    "7",
                    "discussions",
                ]
        )
        #expect(
            endpoint.queryItems
                == [
                    URLQueryItem(
                        name: "per_page",
                        value: "20"
                    ),
                ]
        )
        #expect(endpoint.body == nil)
    }

    @Test("Builds the merge request discussions endpoint")
    func buildsMergeRequestEndpoint() {
        let endpoint = GitLabDiscussionEndpoints.discussions(
            for: .mergeRequest(
                GitLabMergeRequestRoute(
                    projectID: 99,
                    mergeRequestIID: 13
                )
            )
        )

        #expect(endpoint.method == .get)
        #expect(endpoint.requiredAccess == .read)
        #expect(
            endpoint.pathComponents
                == [
                    "projects",
                    "99",
                    "merge_requests",
                    "13",
                    "discussions",
                ]
        )
        #expect(
            endpoint.queryItems
                == [
                    URLQueryItem(
                        name: "per_page",
                        value: "20"
                    ),
                ]
        )
    }
}
