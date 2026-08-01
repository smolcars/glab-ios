import Foundation
@testable import Glab

nonisolated func makeTestTodo(
    id: Int = 102,
    title: String = "Review authentication changes",
    body: String? = "Please review the token refresh path.",
    state: GitLabTodoState = .pending,
    targetType: GitLabTodoTargetType = .mergeRequest,
    createdAt: Date =
        Date(timeIntervalSince1970: 1_785_168_765)
) -> GitLabTodo {
    GitLabTodo(
        id: id,
        project: GitLabTodoProject(
            id: 2,
            name: "Glab iOS",
            nameWithNamespace: "Mobile / Glab iOS",
            path: "glab-ios",
            pathWithNamespace: "mobile/glab-ios"
        ),
        author: makeTestAPIUser(
            id: 8,
            username: "ada",
            name: "Ada Lovelace"
        ),
        action: .approvalRequired,
        targetType: targetType,
        target: GitLabTodoTarget(
            id: 34,
            iid: 7,
            projectID: 2,
            title: title,
            name: nil,
            description: nil,
            state: "opened"
        ),
        targetURL: URL(
            string:
                "https://gitlab.example.com/mobile/glab-ios/"
                + "-/merge_requests/7"
        ),
        body: body,
        state: state,
        createdAt: createdAt,
        updatedAt: Date(timeIntervalSince1970: 1_785_172_400)
    )
}
