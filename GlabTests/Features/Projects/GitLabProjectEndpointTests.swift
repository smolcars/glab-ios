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
                "membership",
                100
            ),
            (
                GitLabProjectListMode.starred,
                "starred",
                20
            ),
        ]
    )
    func buildsListQuery(
        mode: GitLabProjectListMode,
        filter: String,
        perPage: Int
    ) throws {
        let url = try requestURL(
            GitLabProjectEndpoints.projects(for: mode)
        )

        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/projects"
                + "?\(filter)=true"
                + "&order_by=last_activity_at&sort=desc"
                + "&simple=true&per_page=\(perPage)"
        )
    }

    @Test("Encodes a namespaced path as one project identifier")
    func buildsProjectByPathRequest() throws {
        let endpoint = GitLabProjectEndpoints.project(
            pathWithNamespace:
                "group/subgroup/glab ios"
        )
        let url = try requestURL(endpoint)

        #expect(endpoint.requiredAccess == .read)
        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/group%2Fsubgroup%2Fglab%20ios"
        )
    }

    @Test(
        "Builds project star mutations",
        arguments: [true, false]
    )
    func buildsStarMutation(
        isStarred: Bool
    ) throws {
        let endpoint =
            isStarred
            ? GitLabProjectEndpoints.star(
                projectID: 42
            )
            : GitLabProjectEndpoints.unstar(
                projectID: 42
            )
        let request = try request(endpoint)
        let url = try #require(request.url)

        #expect(endpoint.method == .post)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/"
                + (isStarred ? "star" : "unstar")
        )
    }
}

private extension GitLabProjectEndpointTests {
    nonisolated func requestURL<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URL {
        #expect(endpoint.requiredAccess == .read)
        let request = try request(endpoint)

        return try #require(request.url)
    }

    nonisolated func request<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URLRequest {
        try GitLabRequestBuilder(
            host: GitLabHost("gitlab.example.com"),
            authorization: .personalAccessToken("pat-secret")
        ).build(endpoint)
    }
}
