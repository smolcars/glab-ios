import Foundation
import Testing
@testable import Glab

@Suite("GitLab merge request endpoints")
struct GitLabMergeRequestEndpointTests {
    @Test(
        "Builds the open merge request list query",
        arguments: [
            (
                GitLabMergeRequestListMode.assigned,
                "assigned_to_me"
            ),
            (
                GitLabMergeRequestListMode.reviewRequested,
                "reviews_for_me"
            ),
        ]
    )
    func buildsListQuery(
        mode: GitLabMergeRequestListMode,
        scope: String
    ) throws {
        let url = try requestURL(
            GitLabMergeRequestEndpoints.mergeRequests(
                for: mode
            )
        )

        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/merge_requests"
                + "?scope=\(scope)&state=opened"
                + "&order_by=updated_at&sort=desc&per_page=20"
        )
    }

    @Test("Builds a project merge request detail route")
    func buildsDetailRoute() throws {
        let url = try requestURL(
            GitLabMergeRequestEndpoints.mergeRequest(
                at: GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 7
                )
            )
        )

        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/projects/42"
                + "/merge_requests/7"
        )
    }
}

private extension GitLabMergeRequestEndpointTests {
    nonisolated func requestURL<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URL {
        let request = try GitLabRequestBuilder(
            host: GitLabHost("gitlab.example.com"),
            authorization: .personalAccessToken("pat-secret")
        ).build(endpoint)

        return try #require(request.url)
    }
}
