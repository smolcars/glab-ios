import Foundation
import Testing
@testable import Glab

@Suite("GitLab Todo contract")
struct GitLabTodoTests {
    @Test("Decodes inbox presentation fields")
    func decodesTodo() throws {
        let todo = try decodeTodo()

        #expect(todo.id == 102)
        #expect(todo.project?.nameWithNamespace == "Mobile / Glab iOS")
        #expect(todo.author?.displayName == "Ada Lovelace")
        #expect(todo.action == .approvalRequired)
        #expect(todo.targetType == .mergeRequest)
        #expect(todo.target?.iid == 7)
        #expect(todo.title == "Review authentication changes")
        #expect(todo.displayBody == "Please review the token refresh path.")
        #expect(todo.projectTitle == "Mobile / Glab iOS")
        #expect(todo.authorTitle == "Ada Lovelace")
        #expect(todo.state == .pending)
        #expect(
            todo.createdAt
                == Date(timeIntervalSince1970: 1_785_168_765)
        )
        #expect(
            todo.updatedAt
                == Date(timeIntervalSince1970: 1_785_172_400)
        )
        #expect(todo.safeTargetURL?.scheme == "https")
    }

    @Test(
        "Decodes every documented target type and an unknown value",
        arguments: [
            ("Issue", GitLabTodoTargetType.issue),
            ("MergeRequest", .mergeRequest),
            ("Commit", .commit),
            ("Epic", .epic),
            ("DesignManagement::Design", .design),
            ("AlertManagement::Alert", .alert),
            ("Project", .project),
            ("Namespace", .namespace),
            ("Vulnerability", .vulnerability),
            ("WikiPage::Meta", .wikiPage),
            ("WorkItem", .unknown("WorkItem")),
        ]
    )
    func decodesTargetType(
        value: String,
        expected: GitLabTodoTargetType
    ) throws {
        let decoded = try JSONDecoder().decode(
            GitLabTodoTargetType.self,
            from: Data("\"\(value)\"".utf8)
        )

        #expect(decoded == expected)
        #expect(!decoded.title.isEmpty)
        #expect(!decoded.systemImage.isEmpty)
    }

    @Test(
        "Decodes every documented action and an unknown value",
        arguments: [
            ("assigned", GitLabTodoAction.assigned),
            ("mentioned", .mentioned),
            ("build_failed", .buildFailed),
            ("marked", .marked),
            ("approval_required", .approvalRequired),
            ("unmergeable", .unmergeable),
            ("directly_addressed", .directlyAddressed),
            ("merge_train_removed", .mergeTrainRemoved),
            ("member_access_requested", .memberAccessRequested),
            ("future_action", .unknown("future_action")),
        ]
    )
    func decodesAction(
        value: String,
        expected: GitLabTodoAction
    ) throws {
        let decoded = try JSONDecoder().decode(
            GitLabTodoAction.self,
            from: Data("\"\(value)\"".utf8)
        )

        #expect(decoded == expected)
        #expect(!decoded.title.isEmpty)
    }

    @Test("Uses neutral fallbacks for missing containers")
    func decodesMissingOptionalData() throws {
        let todo = try decodeTodo(
            project: "null",
            author: "null",
            target: "null",
            targetURL: "null",
            body: "null"
        )

        #expect(todo.project == nil)
        #expect(todo.author == nil)
        #expect(todo.target == nil)
        #expect(todo.title == "Untitled Todo")
        #expect(todo.displayBody == nil)
        #expect(todo.projectTitle == "No project")
        #expect(todo.authorTitle == "Unknown author")
        #expect(todo.safeTargetURL == nil)
    }

    @Test("Uses target name and then body as title fallbacks")
    func selectsTitleFallbacks() throws {
        let named = try decodeTodo(
            target: """
                {
                  "id": 34,
                  "name": "Security review"
                }
                """,
            body: #""Different body""#
        )
        let bodyOnly = try decodeTodo(
            target: "null",
            body: #""Body title""#
        )
        let repeated = try decodeTodo(
            target: """
                {
                  "id": 34,
                  "title": "Same title"
                }
                """,
            body: #"" Same title ""#
        )

        #expect(named.title == "Security review")
        #expect(named.displayBody == "Different body")
        #expect(bodyOnly.title == "Body title")
        #expect(bodyOnly.displayBody == nil)
        #expect(repeated.displayBody == nil)
    }

    @Test("Rejects an unsafe target URL")
    func rejectsUnsafeTargetURL() throws {
        let todo = try decodeTodo(
            targetURL:
                #""https://user@gitlab.example.com/mobile/glab-ios""#
        )

        #expect(todo.safeTargetURL == nil)
    }
}

private extension GitLabTodoTests {
    func decodeTodo(
        project: String = """
            {
              "id": 2,
              "name": "Glab iOS",
              "name_with_namespace": "Mobile / Glab iOS",
              "path": "glab-ios",
              "path_with_namespace": "mobile/glab-ios"
            }
            """,
        author: String = """
            {
              "id": 8,
              "username": "ada",
              "name": "Ada Lovelace",
              "avatar_url": null,
              "web_url": "https://gitlab.example.com/ada"
            }
            """,
        target: String = """
            {
              "id": 34,
              "iid": 7,
              "project_id": 2,
              "title": "Review authentication changes",
              "description": "Refresh token changes",
              "state": "opened"
            }
            """,
        targetURL: String =
            #""https://gitlab.example.com/mobile/glab-ios/-/merge_requests/7""#,
        body: String =
            #""Please review the token refresh path.""#
    ) throws -> GitLabTodo {
        let data = Data(
            """
            {
              "id": 102,
              "project": \(project),
              "author": \(author),
              "action_name": "approval_required",
              "target_type": "MergeRequest",
              "target": \(target),
              "target_url": \(targetURL),
              "body": \(body),
              "state": "pending",
              "created_at": "2026-07-27T16:12:45Z",
              "updated_at": "2026-07-27T17:13:20Z"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(
            GitLabTodo.self,
            from: data
        )
    }
}
