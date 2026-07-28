import Foundation
import Testing
@testable import Glab

@Suite("GitLab search result contracts")
struct GitLabSearchResultTests {
    @Test("Decodes a sparse project search result and ignores unknown fields")
    func decodesProject() throws {
        let result = try decodeResult(
            """
            {
              "id": 42,
              "name": "Glab iOS",
              "name_with_namespace": "Mobile / Glab iOS",
              "path_with_namespace": "mobile/glab-ios",
              "description": null,
              "web_url": "https://gitlab.example.com/mobile/glab-ios",
              "unknown_future_field": {"enabled": true}
            }
            """
        )

        guard case let .project(project) = result else {
            Issue.record("Expected a project search result")
            return
        }

        #expect(project.id == 42)
        #expect(project.name == "Glab iOS")
        #expect(
            project.nameWithNamespace
                == "Mobile / Glab iOS"
        )
        #expect(
            project.pathWithNamespace
                == "mobile/glab-ios"
        )
        #expect(project.description == nil)
        #expect(
            project.safeWebURL?.absoluteString
                == "https://gitlab.example.com/mobile/glab-ios"
        )
        #expect(project.visibility == nil)
        #expect(project.lastActivityAt == nil)
        #expect(
            result.nativeRoute == .project(
                GitLabProjectRoute(
                    pathWithNamespace:
                        "mobile/glab-ios"
                )
            )
        )
    }

    @Test("Decodes a sparse issue search result without detail-only references")
    func decodesIssue() throws {
        let result = try decodeResult(
            """
            {
              "id": 101,
              "iid": 7,
              "project_id": 42,
              "title": "Fix pagination",
              "state": "opened",
              "labels": ["bug"],
              "updated_at": "2026-07-25T12:00:00Z",
              "web_url": "https://gitlab.example.com/mobile/glab-ios/-/issues/7",
              "unknown_future_field": true
            }
            """
        )

        guard case let .issue(issue) = result else {
            Issue.record("Expected an issue search result")
            return
        }

        #expect(issue.id == 101)
        #expect(issue.route == GitLabIssueRoute(projectID: 42, issueIID: 7))
        #expect(issue.title == "Fix pagination")
        #expect(issue.state == "opened")
        #expect(issue.labels == ["bug"])
        #expect(issue.author == nil)
        #expect(issue.confidential == false)
        #expect(
            result.nativeRoute
                == .issue(issue.route)
        )
    }

    @Test("Decodes a sparse merge request search result with defensive defaults")
    func decodesMergeRequest() throws {
        let result = try decodeResult(
            """
            {
              "id": 201,
              "iid": 8,
              "project_id": 42,
              "title": "Review pagination",
              "state": "opened",
              "draft": true,
              "updated_at": "2026-07-25T12:00:00Z",
              "web_url": "https://gitlab.example.com/mobile/glab-ios/-/merge_requests/8",
              "unknown_future_field": ["value"]
            }
            """
        )

        guard case let .mergeRequest(mergeRequest) = result else {
            Issue.record("Expected a merge request search result")
            return
        }

        #expect(mergeRequest.id == 201)
        #expect(
            mergeRequest.route
                == GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 8
                )
        )
        #expect(mergeRequest.title == "Review pagination")
        #expect(mergeRequest.state == "opened")
        #expect(mergeRequest.isDraft)
        #expect(mergeRequest.labels.isEmpty)
        #expect(mergeRequest.author == nil)
        #expect(
            result.nativeRoute
                == .mergeRequest(
                    mergeRequest.route
                )
        )
    }

    @Test("Includes the account in stable search result identity")
    func includesAccountInIdentity() throws {
        let firstAccount = GitLabAccountID(
            host: try GitLabHost("gitlab.example.com"),
            userID: 1
        )
        let secondAccount = GitLabAccountID(
            host: try GitLabHost("gitlab.example.com"),
            userID: 2
        )
        let resource =
            GitLabSearchResourceID.issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )

        let first = GitLabSearchResultID(
            accountID: firstAccount,
            resource: resource
        )
        let duplicate = GitLabSearchResultID(
            accountID: firstAccount,
            resource: resource
        )
        let otherAccount = GitLabSearchResultID(
            accountID: secondAccount,
            resource: resource
        )

        #expect(first == duplicate)
        #expect(first != otherAccount)
        #expect(Set([first, duplicate, otherAccount]).count == 2)
    }

    @Test("Builds a bounded single-line summary preview")
    func buildsBoundedSummaryPreview() throws {
        let longDescription =
            "## Why\n\n"
            + String(
                repeating: "responsive search ",
                count: 20
            )
        let result = try decodeResult(
            """
            {
              "id": 101,
              "iid": 7,
              "project_id": 42,
              "title": "Fix pagination",
              "description": \(jsonString(longDescription)),
              "state": "opened",
              "updated_at": "2026-07-25T12:00:00Z",
              "web_url": "https://gitlab.example.com/mobile/glab-ios/-/issues/7"
            }
            """
        )

        let preview = try #require(
            result.summaryPreview
        )
        #expect(
            preview.hasPrefix(
                "## Why responsive search"
            )
        )
        #expect(!preview.contains("\n"))
        #expect(preview.count == 181)
        #expect(preview.hasSuffix("…"))
    }

    @Test("Omits an empty summary preview")
    func omitsEmptySummaryPreview() throws {
        let result = try decodeResult(
            """
            {
              "id": 101,
              "iid": 7,
              "project_id": 42,
              "title": "Fix pagination",
              "description": "  \\n\\t ",
              "state": "opened",
              "updated_at": "2026-07-25T12:00:00Z",
              "web_url": "https://gitlab.example.com/mobile/glab-ios/-/issues/7"
            }
            """
        )

        #expect(result.summaryPreview == nil)
    }
}

private extension GitLabSearchResultTests {
    func jsonString(
        _ value: String
    ) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try #require(
            String(
                data: data,
                encoding: .utf8
            )
        )
    }

    func decodeResult(
        _ json: String
    ) throws -> GitLabSearchResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if json.contains(#""project_id""#) {
            if json.contains(#""draft""#) {
                return .mergeRequest(
                    try decoder.decode(
                        GitLabMergeRequestSearchResult.self,
                        from: Data(json.utf8)
                    )
                )
            }
            return .issue(
                try decoder.decode(
                    GitLabIssueSearchResult.self,
                    from: Data(json.utf8)
                )
            )
        }

        return .project(
            try decoder.decode(
                GitLabProjectSearchResult.self,
                from: Data(json.utf8)
            )
        )
    }
}
