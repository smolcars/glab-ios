import Foundation
import Testing
@testable import Glab

@Suite("GitLab issue endpoints")
struct GitLabIssueEndpointTests {
    @Test("Builds the assigned open issues query")
    func buildsAssignedIssuesQuery() throws {
        let url = try requestURL(
            GitLabIssueEndpoints.assignedIssues
        )

        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/issues"
                + "?scope=assigned_to_me&state=opened"
                + "&order_by=updated_at&sort=desc&per_page=20"
        )
    }

    @Test("Builds a project issue detail route")
    func buildsIssueDetailRoute() throws {
        let url = try requestURL(
            GitLabIssueEndpoints.issue(
                at: GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )
        )

        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/projects/42/issues/7"
        )
    }
}

private extension GitLabIssueEndpointTests {
    nonisolated func requestURL<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URL {
        #expect(endpoint.requiredAccess == .read)
        let request = try GitLabRequestBuilder(
            host: GitLabHost("gitlab.example.com"),
            authorization: .personalAccessToken("pat-secret")
        ).build(endpoint)

        return try #require(request.url)
    }
}
