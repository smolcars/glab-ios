import Foundation
import Testing
@testable import Glab

@Suite("GitLab emoji reaction endpoints")
struct GitLabEmojiReactionEndpointTests {
    @Test(
        "Builds resource list endpoints",
        arguments: resourceCases
    )
    func buildsResourceList(
        awardable: GitLabEmojiAwardable,
        expectedPath: [String]
    ) {
        let endpoint =
            GitLabEmojiReactionEndpoints
                .reactions(for: awardable)

        #expect(endpoint.method == .get)
        #expect(endpoint.requiredAccess == .read)
        #expect(
            endpoint.pathComponents
                == expectedPath + ["award_emoji"]
        )
        #expect(
            endpoint.queryItems
                == [
                    URLQueryItem(
                        name: "per_page",
                        value: "100"
                    ),
                ]
        )
    }

    @Test(
        "Builds note list endpoints",
        arguments: noteCases
    )
    func buildsNoteList(
        awardable: GitLabEmojiAwardable,
        expectedPath: [String]
    ) {
        let endpoint =
            GitLabEmojiReactionEndpoints
                .reactions(for: awardable)

        #expect(
            endpoint.pathComponents
                == expectedPath + ["award_emoji"]
        )
    }

    @Test(
        "Builds add endpoints with names without colons",
        arguments: resourceCases + noteCases
    )
    func buildsAdd(
        awardable: GitLabEmojiAwardable,
        expectedPath: [String]
    ) {
        let endpoint =
            GitLabEmojiReactionEndpoints.add(
                name: "thumbsup",
                to: awardable
            )

        #expect(endpoint.method == .post)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            endpoint.pathComponents
                == expectedPath + ["award_emoji"]
        )
        #expect(
            endpoint.queryItems
                == [
                    URLQueryItem(
                        name: "name",
                        value: "thumbsup"
                    ),
                ]
        )
        #expect(endpoint.body == nil)
    }

    @Test(
        "Builds delete endpoints with exact award IDs",
        arguments: resourceCases + noteCases
    )
    func buildsDelete(
        awardable: GitLabEmojiAwardable,
        expectedPath: [String]
    ) {
        let endpoint =
            GitLabEmojiReactionEndpoints.remove(
                awardID: 91,
                from: awardable
            )

        #expect(endpoint.method == .delete)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            endpoint.pathComponents
                == expectedPath
                    + ["award_emoji", "91"]
        )
        #expect(endpoint.queryItems.isEmpty)
        #expect(endpoint.body == nil)
    }

    nonisolated private static let issueResource:
        GitLabDiscussionResource =
            .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )

    nonisolated private static let mergeRequestResource:
        GitLabDiscussionResource =
            .mergeRequest(
                GitLabMergeRequestRoute(
                    projectID: 99,
                    mergeRequestIID: 13
                )
            )

    nonisolated private static let resourceCases: [
        (
            awardable: GitLabEmojiAwardable,
            expectedPath: [String]
        )
    ] = [
        (
            .resource(issueResource),
            [
                "projects",
                "42",
                "issues",
                "7",
            ]
        ),
        (
            .resource(mergeRequestResource),
            [
                "projects",
                "99",
                "merge_requests",
                "13",
            ]
        ),
    ]

    nonisolated private static let noteCases: [
        (
            awardable: GitLabEmojiAwardable,
            expectedPath: [String]
        )
    ] = [
        (
            .note(
                id: 101,
                in: issueResource
            ),
            [
                "projects",
                "42",
                "issues",
                "7",
                "notes",
                "101",
            ]
        ),
        (
            .note(
                id: 202,
                in: mergeRequestResource
            ),
            [
                "projects",
                "99",
                "merge_requests",
                "13",
                "notes",
                "202",
            ]
        ),
    ]
}
