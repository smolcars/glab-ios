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

    @Test("Builds a write-scoped issue title update")
    func buildsIssueTitleUpdate() throws {
        let endpoint = try GitLabIssueEndpoints.update(
            at: GitLabIssueRoute(
                projectID: 42,
                issueIID: 7
            ),
            changes: GitLabResourceEditChanges(
                title: "Preserve 👩🏽‍💻 Unicode"
            )
        )
        let request = try buildRequest(endpoint)

        #expect(endpoint.method == .put)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/api/v4/projects/42/issues/7"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "Content-Type"
            ) == "application/json"
        )
        #expect(
            try jsonObject(request)
                == [
                    "title":
                        "Preserve 👩🏽‍💻 Unicode",
                ]
        )
    }

    @Test("Builds an explicit empty issue description update")
    func buildsEmptyIssueDescriptionUpdate() throws {
        let endpoint = try GitLabIssueEndpoints.update(
            at: GitLabIssueRoute(
                projectID: 42,
                issueIID: 7
            ),
            changes: GitLabResourceEditChanges(
                description: ""
            )
        )
        let request = try buildRequest(endpoint)

        #expect(
            try jsonObject(request)
                == ["description": ""]
        )
        let bodyData = try #require(
            request.httpBody
        )
        let body = try #require(
            String(
                data: bodyData,
                encoding: .utf8
            )
        )
        #expect(!body.contains("title"))
    }
}

private extension GitLabIssueEndpointTests {
    nonisolated func requestURL<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URL {
        #expect(endpoint.requiredAccess == .read)
        let request = try buildRequest(endpoint)

        return try #require(request.url)
    }

    nonisolated func buildRequest<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URLRequest {
        try GitLabRequestBuilder(
            host: GitLabHost("gitlab.example.com"),
            authorization: .personalAccessToken("pat-secret")
        ).build(endpoint)
    }

    nonisolated func jsonObject(
        _ request: URLRequest
    ) throws -> [String: String] {
        let body = try #require(request.httpBody)
        return try #require(
            JSONSerialization.jsonObject(
                with: body
            ) as? [String: String]
        )
    }
}
