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

    @Test("Builds the all-tier merge request approvals route")
    func buildsApprovalsRoute() throws {
        let endpoint =
            GitLabMergeRequestEndpoints.approvals(
                at: GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 7
                )
            )
        let url = try requestURL(endpoint)

        #expect(endpoint.method == .get)
        #expect(
            endpoint.pathComponents
                == [
                    "projects",
                    "42",
                    "merge_requests",
                    "7",
                    "approvals",
                ]
        )
        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/projects/42"
                + "/merge_requests/7/approvals"
        )
    }

    @Test("Builds a head-aware paginated diff route")
    func buildsDiffRoute() throws {
        let endpoint =
            GitLabMergeRequestDiffEndpoints.diffs(
                at: GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 7
                ),
                headSHA: "private-head-sha"
            )
        let url = try requestURL(endpoint)

        #expect(endpoint.method == .get)
        #expect(
            endpoint.pathComponents
                == [
                    "projects",
                    "42",
                    "merge_requests",
                    "7",
                    "diffs",
                ]
        )
        #expect(
            endpoint.queryItems
                == [
                    URLQueryItem(
                        name: "per_page",
                        value: "20"
                    ),
                ]
        )
        #expect(
            endpoint.cacheVariant
                == "private-head-sha"
        )
        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/projects/42"
                + "/merge_requests/7/diffs?per_page=20"
        )
        #expect(
            !url.absoluteString
                .contains("private-head-sha")
        )
    }

    @Test("Builds a write-scoped merge request update")
    func buildsMergeRequestUpdate() throws {
        let endpoint =
            try GitLabMergeRequestEndpoints.update(
                at: GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 7
                ),
                changes: GitLabResourceEditChanges(
                    title: "Updated title",
                    description:
                        "# Exact Markdown\n\n- [ ] Keep this"
                )
            )
        let request = try buildRequest(endpoint)

        #expect(endpoint.method == .put)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/api/v4/projects/42"
                + "/merge_requests/7"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "Content-Type"
            ) == "application/json"
        )
        #expect(
            try jsonObject(request)
                == [
                    "description":
                        "# Exact Markdown\n\n- [ ] Keep this",
                    "title": "Updated title",
                ]
        )
    }

    @Test("Omits an unchanged merge request description field")
    func omitsMergeRequestDescription() throws {
        let endpoint =
            try GitLabMergeRequestEndpoints.update(
                at: GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 7
                ),
                changes: GitLabResourceEditChanges(
                    title: "Only the title"
                )
            )
        let request = try buildRequest(endpoint)

        #expect(
            try jsonObject(request)
                == ["title": "Only the title"]
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
        #expect(!body.contains("description"))
    }

    @Test("Builds merge request label deltas with exact values")
    func buildsMergeRequestLabelDelta() throws {
        let endpoint =
            try GitLabMergeRequestEndpoints
                .updateMetadata(
                    at: GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 7
                    ),
                    changes:
                        GitLabResourceMetadataChanges(
                            labels:
                                .delta(
                                    add: [
                                        "status::ready",
                                        "mobile UI 👩🏽‍💻",
                                    ],
                                    remove: [
                                        "needs/triage & docs",
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
                == "status::ready,mobile UI 👩🏽‍💻"
        )
        #expect(
            json["remove_labels"] as? String
                == "needs/triage & docs"
        )
    }

    @Test("Builds merge request people and close fields together")
    func buildsMergeRequestPeopleAndState() throws {
        let endpoint =
            try GitLabMergeRequestEndpoints
                .updateMetadata(
                    at: GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 7
                    ),
                    changes:
                        GitLabResourceMetadataChanges(
                            assigneeIDs: [17, 23],
                            reviewerIDs: [31, 37],
                            stateEvent: .close
                        )
                )
        let json = try jsonAnyObject(
            buildRequest(endpoint)
        )

        #expect(
            json["assignee_ids"] as? [Int]
                == [17, 23]
        )
        #expect(
            json["reviewer_ids"] as? [Int]
                == [31, 37]
        )
        #expect(
            json["state_event"] as? String == "close"
        )
        #expect(json["assignee_id"] == nil)
    }

    @Test("Builds explicit empty merge request people arrays")
    func buildsEmptyMergeRequestPeople() throws {
        let endpoint =
            try GitLabMergeRequestEndpoints
                .updateMetadata(
                    at: GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 7
                    ),
                    changes:
                        GitLabResourceMetadataChanges(
                            assigneeIDs: [],
                            reviewerIDs: []
                        )
                )
        let json = try jsonAnyObject(
            buildRequest(endpoint)
        )

        #expect(
            json["assignee_ids"] as? [Int] == []
        )
        #expect(
            json["reviewer_ids"] as? [Int] == []
        )
    }

    @Test("Builds an explicit complete merge request label replacement")
    func buildsMergeRequestLabelReplacement() throws {
        let endpoint =
            try GitLabMergeRequestEndpoints
                .updateMetadata(
                    at: GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 7
                    ),
                    changes:
                        GitLabResourceMetadataChanges(
                            labels:
                                .replacement(
                                    [
                                        "team::iOS",
                                        "QA \"passed\" ✅",
                                    ]
                                )
                        )
                )

        let json = try jsonAnyObject(
            buildRequest(endpoint)
        )

        #expect(
            json["labels"] as? String
                == "team::iOS,QA \"passed\" ✅"
        )
    }
}

private extension GitLabMergeRequestEndpointTests {
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
}
