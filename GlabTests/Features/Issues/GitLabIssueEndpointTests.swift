import Foundation
import Testing
@testable import Glab

@Suite("GitLab issue endpoints")
struct GitLabIssueEndpointTests {
    @Test(
        "Builds open issue list scopes",
        arguments: [
            (
                GitLabIssueListMode.assigned,
                "assigned_to_me"
            ),
            (
                GitLabIssueListMode.created,
                "created_by_me"
            ),
        ]
    )
    func buildsIssuesQuery(
        mode: GitLabIssueListMode,
        scope: String
    ) throws {
        let url = try requestURL(
            GitLabIssueEndpoints.issues(
                for: mode
            )
        )

        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/issues"
                + "?scope=\(scope)&state=opened"
                + "&order_by=updated_at&sort=desc&per_page=20"
        )
    }

    @Test(
        "Builds a state-filtered project issues query",
        arguments:
            GitLabProjectIssueState.allCases
    )
    func buildsProjectIssuesQuery(
        _ state: GitLabProjectIssueState
    ) throws {
        let url = try requestURL(
            GitLabIssueEndpoints.projectIssues(
                projectID: 42,
                state: state
            )
        )

        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/projects/42/issues"
                + "?scope=all&state=\(state.rawValue)"
                + "&order_by=updated_at"
                + "&sort=desc&per_page=20"
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

    @Test("Builds additive issue label changes with exact special characters")
    func buildsIssueLabelDelta() throws {
        let endpoint =
            try GitLabIssueEndpoints
                .updateMetadata(
                    at: GitLabIssueRoute(
                        projectID: 42,
                        issueIID: 7
                    ),
                    changes:
                        GitLabResourceMetadataChanges(
                            labels:
                                .delta(
                                    add: [
                                        "team::iOS",
                                        "needs \"QA\" 👩🏽‍💻",
                                    ],
                                    remove: [
                                        "old/label & stale",
                                    ]
                                )
                        )
                )
        let request = try buildRequest(endpoint)
        let json = try jsonAnyObject(request)

        #expect(endpoint.method == .put)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            json["add_labels"] as? String
                == "team::iOS,needs \"QA\" 👩🏽‍💻"
        )
        #expect(
            json["remove_labels"] as? String
                == "old/label & stale"
        )
    }

    @Test("Builds an explicit complete issue label removal")
    func buildsIssueLabelReplacement() throws {
        let endpoint =
            try GitLabIssueEndpoints
                .updateMetadata(
                    at: GitLabIssueRoute(
                        projectID: 42,
                        issueIID: 7
                    ),
                    changes:
                        GitLabResourceMetadataChanges(
                            labels:
                                .replacement([])
                        )
                )

        let json = try jsonAnyObject(
            buildRequest(endpoint)
        )

        #expect(json["labels"] as? String == "")
    }

    @Test("Builds documented issue assignee replacement shapes")
    func buildsIssueAssignees() throws {
        let empty = try issueAssigneeJSON(ids: [])
        #expect(empty["assignee_ids"] as? [Int] == [])
        #expect(empty["assignee_id"] == nil)

        let single = try issueAssigneeJSON(ids: [17])
        #expect(single["assignee_id"] as? Int == 17)
        #expect(single["assignee_ids"] == nil)

        let multiple = try issueAssigneeJSON(
            ids: [17, 23]
        )
        #expect(
            multiple["assignee_ids"] as? [Int]
                == [17, 23]
        )
        #expect(multiple["assignee_id"] == nil)
    }

    @Test(
        "Builds issue close and reopen state events",
        arguments: [
            GitLabResourceStateEvent.close,
            GitLabResourceStateEvent.reopen,
        ]
    )
    func buildsIssueStateEvent(
        event: GitLabResourceStateEvent
    ) throws {
        let endpoint =
            try GitLabIssueEndpoints
                .updateMetadata(
                    at: GitLabIssueRoute(
                        projectID: 42,
                        issueIID: 7
                    ),
                    changes:
                        GitLabResourceMetadataChanges(
                            stateEvent: event
                        )
                )

        let json = try jsonAnyObject(
            buildRequest(endpoint)
        )

        #expect(
            json["state_event"] as? String
                == event.rawValue
        )
    }

    @Test("Rejects merge-request-only reviewers for an issue")
    func rejectsIssueReviewers() {
        #expect(
            throws:
                GitLabResourceMetadataValidationError
                    .reviewersUnsupported
        ) {
            try GitLabIssueEndpoints
                .updateMetadata(
                    at: GitLabIssueRoute(
                        projectID: 42,
                        issueIID: 7
                    ),
                    changes:
                        GitLabResourceMetadataChanges(
                            reviewerIDs: [17]
                        )
                )
        }
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

    nonisolated func jsonAnyObject(
        _ request: URLRequest
    ) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(
            JSONSerialization.jsonObject(
                with: body
            ) as? [String: Any]
        )
    }

    nonisolated func issueAssigneeJSON(
        ids: [Int]
    ) throws -> [String: Any] {
        let endpoint =
            try GitLabIssueEndpoints
                .updateMetadata(
                    at: GitLabIssueRoute(
                        projectID: 42,
                        issueIID: 7
                    ),
                    changes:
                        GitLabResourceMetadataChanges(
                            assigneeIDs: ids
                        )
                )

        return try jsonAnyObject(
            buildRequest(endpoint)
        )
    }
}
