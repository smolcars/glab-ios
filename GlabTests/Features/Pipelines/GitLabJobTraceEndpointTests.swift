import Foundation
import Testing
@testable import Glab

@Suite("GitLab job trace endpoint")
struct GitLabJobTraceEndpointTests {
    @Test("Builds the documented read-only raw trace request")
    func buildsTraceRequest() throws {
        let endpoint =
            GitLabJobTraceEndpoints.trace(
                at: try route()
            )

        #expect(endpoint.requiredAccess == .read)
        #expect(
            endpoint.pathComponents
                == [
                    "projects",
                    "42",
                    "jobs",
                    "910",
                    "trace",
                ]
        )
        #expect(endpoint.queryItems.isEmpty)

        let request = try GitLabRequestBuilder(
            host:
                GitLabHost(
                    "https://gitlab.example.com/company"
                ),
            authorization:
                .oauth(
                    accessToken:
                        "test-oauth-secret"
                )
        )
        .build(endpoint)

        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/company"
                + "/api/v4/projects/42/jobs/910/trace"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "Accept"
            )
                == "text/plain, application/octet-stream, */*"
        )
        #expect(
            request.value(
                forHTTPHeaderField:
                    "Authorization"
            )
                == "Bearer test-oauth-secret"
        )
    }

    @Test("Trace route requires positive project and job IDs")
    func validatesRoute() {
        #expect(
            GitLabJobTraceRoute(
                projectID: 42,
                jobID: 910
            ) != nil
        )
        #expect(
            GitLabJobTraceRoute(
                projectID: 0,
                jobID: 910
            ) == nil
        )
        #expect(
            GitLabJobTraceRoute(
                projectID: 42,
                jobID: -1
            ) == nil
        )
    }

    @Test("Existing JSON requests keep their JSON Accept header")
    func preservesJSONRequestBehavior() throws {
        let endpoint =
            GitLabAPIRequest<GitLabEmptyResponse>
            .get(
                requires: .read,
                path: ["projects", "42"]
            )
        let request = try GitLabRequestBuilder(
            host: GitLabHost("gitlab.com"),
            authorization:
                .personalAccessToken(
                    "test-token"
                )
        )
        .build(endpoint)

        #expect(
            request.value(
                forHTTPHeaderField: "Accept"
            ) == "application/json"
        )
    }

    private func route()
        throws -> GitLabJobTraceRoute
    {
        try #require(
            GitLabJobTraceRoute(
                projectID: 42,
                jobID: 910
            )
        )
    }
}
