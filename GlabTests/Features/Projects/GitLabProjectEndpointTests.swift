import Foundation
import Testing
@testable import Glab

@Suite("GitLab project endpoints")
struct GitLabProjectEndpointTests {
    @Test(
        "Builds the project list query",
        arguments: [
            (
                GitLabProjectListMode.recent,
                "membership"
            ),
            (
                GitLabProjectListMode.starred,
                "starred"
            ),
        ]
    )
    func buildsListQuery(
        mode: GitLabProjectListMode,
        filter: String
    ) throws {
        let url = try requestURL(
            GitLabProjectEndpoints.projects(for: mode)
        )

        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/projects"
                + "?\(filter)=true"
                + "&order_by=last_activity_at&sort=desc"
                + "&simple=true&per_page=20"
        )
    }
}

private extension GitLabProjectEndpointTests {
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

