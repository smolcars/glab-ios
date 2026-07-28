import Foundation
import Testing
@testable import Glab

@Suite("GitLab discussion endpoints")
struct GitLabDiscussionEndpointTests {
    @Test("Builds the issue discussions endpoint")
    func buildsIssueEndpoint() {
        let endpoint = GitLabDiscussionEndpoints.discussions(
            for: .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )
        )

        #expect(endpoint.method == .get)
        #expect(endpoint.requiredAccess == .read)
        #expect(
            endpoint.pathComponents
                == [
                    "projects",
                    "42",
                    "issues",
                    "7",
                    "discussions",
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
        #expect(endpoint.body == nil)
    }

    @Test("Builds the merge request discussions endpoint")
    func buildsMergeRequestEndpoint() {
        let endpoint = GitLabDiscussionEndpoints.discussions(
            for: .mergeRequest(
                GitLabMergeRequestRoute(
                    projectID: 99,
                    mergeRequestIID: 13
                )
            )
        )

        #expect(endpoint.method == .get)
        #expect(endpoint.requiredAccess == .read)
        #expect(
            endpoint.pathComponents
                == [
                    "projects",
                    "99",
                    "merge_requests",
                    "13",
                    "discussions",
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
    }

    @Test("Builds the exact merge request discussion endpoint")
    func buildsExactMergeRequestDiscussionEndpoint() {
        let endpoint =
            GitLabDiscussionEndpoints
                .mergeRequestDiscussion(
                    at:
                        GitLabMergeRequestRoute(
                            projectID: 99,
                            mergeRequestIID: 13
                        ),
                    discussionID:
                        "opaque-discussion-id"
                )

        #expect(endpoint.method == .get)
        #expect(endpoint.requiredAccess == .read)
        #expect(
            endpoint.pathComponents
                == [
                    "projects",
                    "99",
                    "merge_requests",
                    "13",
                    "discussions",
                    "opaque-discussion-id",
                ]
        )
        #expect(endpoint.queryItems.isEmpty)
        #expect(endpoint.body == nil)
    }

    @Test(
        "Builds resolve and reopen discussion PUT endpoints",
        arguments: [true, false]
    )
    func buildsResolutionEndpoint(
        resolved: Bool
    ) throws {
        let endpoint =
            try GitLabDiscussionEndpoints
                .setMergeRequestDiscussionResolution(
                    at:
                        GitLabMergeRequestRoute(
                            projectID: 99,
                            mergeRequestIID: 13
                        ),
                    discussionID:
                        "opaque-discussion-id",
                    resolved: resolved
                )

        #expect(endpoint.method == .put)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            endpoint.pathComponents
                == [
                    "projects",
                    "99",
                    "merge_requests",
                    "13",
                    "discussions",
                    "opaque-discussion-id",
                ]
        )
        #expect(endpoint.queryItems.isEmpty)
        #expect(
            try decodedResolvedBody(
                from: endpoint
            ) == resolved
        )
    }

    @Test("Keeps an opaque discussion ID in one encoded path segment")
    func encodesOpaqueDiscussionIdentity() throws {
        let endpoint =
            try GitLabDiscussionEndpoints
                .setMergeRequestDiscussionResolution(
                    at:
                        GitLabMergeRequestRoute(
                            projectID: 99,
                            mergeRequestIID: 13
                        ),
                    discussionID:
                        "opaque/id?part#hash%value",
                    resolved: true
                )
        let request =
            try GitLabRequestBuilder(
                host:
                    GitLabHost(
                        "gitlab.example.com"
                    ),
                authorization:
                    .personalAccessToken(
                        "test-token"
                    )
            )
            .build(endpoint)

        #expect(
            request.url?
                .absoluteString
                == "https://gitlab.example.com/api/v4/"
                    + "projects/99/merge_requests/13/discussions/"
                    + "opaque%2Fid%3Fpart%23hash%25value"
        )
    }

    @Test(
        "Builds new discussion POST endpoints",
        arguments: [
            (
                resource: GitLabDiscussionResource.issue(
                    GitLabIssueRoute(
                        projectID: 42,
                        issueIID: 7
                    )
                ),
                expectedPath: [
                    "projects",
                    "42",
                    "issues",
                    "7",
                    "discussions",
                ]
            ),
            (
                resource:
                    GitLabDiscussionResource
                    .mergeRequest(
                        GitLabMergeRequestRoute(
                            projectID: 99,
                            mergeRequestIID: 13
                        )
                    ),
                expectedPath: [
                    "projects",
                    "99",
                    "merge_requests",
                    "13",
                    "discussions",
                ]
            ),
        ]
    )
    func buildsNewDiscussionEndpoint(
        resource: GitLabDiscussionResource,
        expectedPath: [String]
    ) throws {
        let body = try GitLabDiscussionCommentBody(
            "Please review **this**."
        )
        let endpoint =
            try GitLabDiscussionEndpoints
                .createDiscussion(
                    for: resource,
                    body: body
                )

        #expect(endpoint.method == .post)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            endpoint.pathComponents == expectedPath
        )
        #expect(
            try decodedBody(from: endpoint)
                == body.body
        )
    }

    @Test(
        "Builds reply POST endpoints",
        arguments: [
            (
                resource: GitLabDiscussionResource.issue(
                    GitLabIssueRoute(
                        projectID: 42,
                        issueIID: 7
                    )
                ),
                expectedPrefix: [
                    "projects",
                    "42",
                    "issues",
                    "7",
                    "discussions",
                ]
            ),
            (
                resource:
                    GitLabDiscussionResource
                    .mergeRequest(
                        GitLabMergeRequestRoute(
                            projectID: 99,
                            mergeRequestIID: 13
                        )
                    ),
                expectedPrefix: [
                    "projects",
                    "99",
                    "merge_requests",
                    "13",
                    "discussions",
                ]
            ),
        ]
    )
    func buildsReplyEndpoint(
        resource: GitLabDiscussionResource,
        expectedPrefix: [String]
    ) throws {
        let discussionID =
            "opaque-discussion-id"
        let body = try GitLabDiscussionCommentBody(
            "A threaded reply"
        )
        let endpoint =
            try GitLabDiscussionEndpoints.reply(
                to: discussionID,
                in: resource,
                body: body
            )

        #expect(endpoint.method == .post)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            endpoint.pathComponents
                == expectedPrefix
                + [discussionID, "notes"]
        )
        #expect(
            try decodedBody(from: endpoint)
                == body.body
        )
    }

    @Test(
        "Rejects empty comment bodies",
        arguments: [
            "",
            " ",
            "\n\t",
        ]
    )
    func rejectsEmptyBody(_ value: String) {
        #expect(
            throws:
                GitLabDiscussionCommentBodyError
                .empty
        ) {
            try GitLabDiscussionCommentBody(
                value
            )
        }
    }

    @Test("Preserves nonempty comment text exactly")
    func preservesCommentBody() throws {
        let value = "  Keep surrounding space  \n"

        let body =
            try GitLabDiscussionCommentBody(
                value
            )

        #expect(body.body == value)
        #expect(
            !String(describing: body)
                .contains(value)
        )
        #expect(
            !String(reflecting: body)
                .contains(value)
        )
    }

    private func decodedBody<Response>(
        from endpoint:
            GitLabAPIRequest<Response>
    ) throws -> String
    where Response: Decodable & Sendable {
        let data = try #require(endpoint.body)
        let object = try #require(
            JSONSerialization
                .jsonObject(with: data)
                as? [String: String]
        )
        return try #require(object["body"])
    }

    private func decodedResolvedBody<Response>(
        from endpoint:
            GitLabAPIRequest<Response>
    ) throws -> Bool
    where Response: Decodable & Sendable {
        let data = try #require(endpoint.body)
        let object = try #require(
            JSONSerialization
                .jsonObject(with: data)
                as? [String: Bool]
        )
        return try #require(
            object["resolved"]
        )
    }
}
