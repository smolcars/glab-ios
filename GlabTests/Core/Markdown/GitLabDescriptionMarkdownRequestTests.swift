import Foundation
import Testing
@testable import Glab

@Suite("GitLab description Markdown requests")
struct GitLabDescriptionMarkdownRequestTests {
    @Test("Issue descriptions preserve the exact API source")
    func issueSource() throws {
        let accountID = try makeAccountID()
        let source =
            "\r\n  - [ ] Ship  \r\n"
        let issue = makeTestIssue(
            description: source
        )

        let request = try #require(
            GitLabDescriptionMarkdownRequest
                .issue(
                    accountID: accountID,
                    issue: issue
                )
        )

        #expect(request.source == source)
        #expect(
            request.resource
                == .issue(
                    projectID: issue.projectID,
                    issueIID: issue.iid
                )
        )
    }

    @Test("Merge request descriptions preserve the exact API source")
    func mergeRequestSource() throws {
        let accountID = try makeAccountID()
        let source =
            "\n- [x] Done\t\n"
        let mergeRequest =
            makeTestMergeRequest(
                description: source
            )

        let request = try #require(
            GitLabDescriptionMarkdownRequest
                .mergeRequest(
                    accountID: accountID,
                    mergeRequest:
                        mergeRequest
                )
        )

        #expect(request.source == source)
        #expect(
            request.resource
                == .mergeRequest(
                    projectID:
                        mergeRequest.projectID,
                    mergeRequestIID:
                        mergeRequest.iid
                )
        )
    }

    @Test("Missing and whitespace-only descriptions have no request")
    func emptySource() throws {
        let accountID = try makeAccountID()

        #expect(
            GitLabDescriptionMarkdownRequest
                .issue(
                    accountID: accountID,
                    issue:
                        makeTestIssue(
                            description: nil
                        )
                ) == nil
        )
        #expect(
            GitLabDescriptionMarkdownRequest
                .mergeRequest(
                    accountID: accountID,
                    mergeRequest:
                        makeTestMergeRequest(
                            description:
                                " \r\n\t "
                        )
                ) == nil
        )
    }

    @Test(
        "Todo descriptions use their native GitLab resource context",
        arguments: [
            (
                GitLabTodoTargetType.issue,
                GitLabMarkdownResourceID.issue(
                    projectID: 2,
                    issueIID: 7
                )
            ),
            (
                GitLabTodoTargetType.mergeRequest,
                GitLabMarkdownResourceID.mergeRequest(
                    projectID: 2,
                    mergeRequestIID: 7
                )
            ),
        ]
    )
    func todoResource(
        targetType: GitLabTodoTargetType,
        expected: GitLabMarkdownResourceID
    ) throws {
        let source = "### Notes\n\n- [ ] Verify"
        let todo = makeTestTodo(
            targetType: targetType
        )

        let request = try #require(
            GitLabDescriptionMarkdownRequest
                .todo(
                    accountID: try makeAccountID(),
                    todo: todo,
                    source: source
                )
        )

        #expect(request.resource == expected)
        #expect(request.source == source)
        #expect(request.webURL == todo.safeTargetURL)
    }

    @Test("Non-native Todo targets retain their plain-text fallback")
    func unsupportedTodoTarget() throws {
        #expect(
            GitLabDescriptionMarkdownRequest
                .todo(
                    accountID: try makeAccountID(),
                    todo:
                        makeTestTodo(
                            targetType: .commit
                        ),
                    source: "**Commit details**"
                ) == nil
        )
    }

    private func makeAccountID()
        throws -> GitLabAccountID
    {
        GitLabAccountID(
            host:
                try GitLabHost(
                    "https://gitlab.example.com"
                ),
            userID: 9
        )
    }
}
