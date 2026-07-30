import Foundation
import Testing
@testable import Glab

@Suite("GitLab commit endpoints")
struct GitLabCommitEndpointTests {
    @Test("Uses the project default branch when no ref is supplied")
    func buildsDefaultBranchHistoryRequest()
        throws
    {
        let url = try requestURL(
            GitLabCommitEndpoints.commits(
                projectID: 42,
                refName: nil
            )
        )

        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/repository/commits"
                + "?per_page=20"
        )
    }

    @Test("Scopes commit history to the resolved default branch")
    func buildsNamedBranchHistoryRequest()
        throws
    {
        let url = try requestURL(
            GitLabCommitEndpoints.commits(
                projectID: 42,
                refName: "main"
            )
        )

        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/repository/commits"
                + "?per_page=20&ref_name=main"
        )
    }

    @Test("Builds a commit diff request")
    func buildsDiffRequest() throws {
        let endpoint =
            GitLabCommitEndpoints.diff(
                projectID: 42,
                commitSHA:
                    "ed899a2f4b5"
            )
        let url = try requestURL(endpoint)

        #expect(endpoint.requiredAccess == .read)
        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/repository/commits/"
                + "ed899a2f4b5/diff"
        )
    }
}

private extension GitLabCommitEndpointTests {
    nonisolated func requestURL<Response>(
        _ endpoint:
            GitLabAPIRequest<Response>
    ) throws -> URL {
        let request = try GitLabRequestBuilder(
            host:
                GitLabHost(
                    "gitlab.example.com"
                ),
            authorization:
                .personalAccessToken(
                    "pat-secret"
                )
        )
        .build(endpoint)

        return try #require(request.url)
    }
}
