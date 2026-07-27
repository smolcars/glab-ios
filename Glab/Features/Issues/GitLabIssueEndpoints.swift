import Foundation

nonisolated enum GitLabIssueEndpoints {
    static let assignedIssues:
        GitLabAPIRequest<[GitLabIssue]> = .get(
            path: ["issues"],
            query: [
                .init(name: "scope", value: "assigned_to_me"),
                .init(name: "state", value: "opened"),
                .init(name: "order_by", value: "updated_at"),
                .init(name: "sort", value: "desc"),
                .init(name: "per_page", value: "20"),
            ]
        )

    static func issue(
        at route: GitLabIssueRoute
    ) -> GitLabAPIRequest<GitLabIssue> {
        .get(
            path: [
                "projects",
                String(route.projectID),
                "issues",
                String(route.issueIID),
            ]
        )
    }
}

