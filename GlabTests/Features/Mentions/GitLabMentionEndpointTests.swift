import Foundation
import Testing
@testable import Glab

@Suite("GitLab mention endpoint")
struct GitLabMentionEndpointTests {
    @Test("Builds a compact inherited-member search")
    func buildsMemberSearch() throws {
        let endpoint =
            GitLabProjectMemberEndpoints
                .members(
                    projectID: 42,
                    search: "  nitesh bot  ",
                    perPage: 10
                )
        let request = try GitLabRequestBuilder(
            host:
                GitLabHost(
                    "gitlab.example.com"
                ),
            authorization:
                .personalAccessToken(
                    "pat-secret"
                )
        ).build(endpoint)

        #expect(endpoint.method == .get)
        #expect(
            endpoint.requiredAccess == .read
        )
        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/members/all"
                + "?per_page=10"
                + "&query=nitesh%20bot"
        )
    }
}
