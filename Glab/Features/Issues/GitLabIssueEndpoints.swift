import Foundation

nonisolated enum GitLabIssueEndpoints {
    static let assignedIssues:
        GitLabAPIRequest<[GitLabIssue]> = .get(
            requires: .read,
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
            requires: .read,
            path: [
                "projects",
                String(route.projectID),
                "issues",
                String(route.issueIID),
            ]
        )
    }

    static func update(
        at route: GitLabIssueRoute,
        changes: GitLabResourceEditChanges
    ) throws -> GitLabAPIRequest<GitLabIssue> {
        try .put(
            path: [
                "projects",
                String(route.projectID),
                "issues",
                String(route.issueIID),
            ],
            body: GitLabIssueUpdateBody(
                title: changes.title,
                description: changes.description
            )
        )
    }

    static func updateMetadata(
        at route: GitLabIssueRoute,
        changes: GitLabResourceMetadataChanges
    ) throws -> GitLabAPIRequest<GitLabIssue> {
        try .put(
            path: [
                "projects",
                String(route.projectID),
                "issues",
                String(route.issueIID),
            ],
            body:
                changes.updateBody(
                    allowsReviewers: false
                )
        )
    }

    static func create(
        _ input: GitLabIssueCreationInput
    ) throws -> GitLabAPIRequest<GitLabIssue> {
        try .post(
            requires: .write,
            path: [
                "projects",
                String(input.projectID),
                "issues",
            ],
            body: GitLabIssueCreateBody(
                title: input.title,
                description:
                    input.rawDescription.isEmpty
                    ? nil
                    : input.rawDescription,
                labels:
                    input.labelNames.isEmpty
                    ? nil
                    : input.labelNames.joined(
                        separator: ","
                    ),
                assigneeID:
                    input.assigneeIDs.count == 1
                    ? input.assigneeIDs[0]
                    : nil,
                assigneeIDs:
                    input.assigneeIDs.count > 1
                    ? input.assigneeIDs
                    : nil,
                confidential:
                    input.confidential,
                dueDate:
                    input.dueDate?.apiValue
            )
        )
    }
}

private nonisolated struct GitLabIssueUpdateBody:
    Encodable,
    Sendable
{
    let title: String?
    let description: String?
}

private nonisolated struct GitLabIssueCreateBody:
    Encodable,
    Sendable
{
    let title: String
    let description: String?
    let labels: String?
    let assigneeID: Int?
    let assigneeIDs: [Int]?
    let confidential: Bool
    let dueDate: String?

    private enum CodingKeys:
        String,
        CodingKey
    {
        case title
        case description
        case labels
        case assigneeID = "assignee_id"
        case assigneeIDs = "assignee_ids"
        case confidential
        case dueDate = "due_date"
    }
}
