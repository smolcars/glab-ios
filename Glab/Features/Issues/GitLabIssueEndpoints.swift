import Foundation

nonisolated enum GitLabIssueEndpoints {
    static func issues(
        for mode: GitLabIssueListMode
    ) -> GitLabAPIRequest<[GitLabIssue]> {
        .get(
            requires: .read,
            path: ["issues"],
            query: [
                .init(name: "scope", value: mode.scope),
                .init(name: "state", value: "opened"),
                .init(name: "order_by", value: "updated_at"),
                .init(name: "sort", value: "desc"),
                .init(name: "per_page", value: "20"),
            ]
        )
    }

    static var assignedIssues:
        GitLabAPIRequest<[GitLabIssue]>
    {
        issues(for: .assigned)
    }

    static func projectIssues(
        projectID: Int,
        state: GitLabProjectIssueState
    ) -> GitLabAPIRequest<[GitLabIssue]> {
        .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "issues",
            ],
            query: [
                .init(name: "scope", value: "all"),
                .init(
                    name: "state",
                    value: state.rawValue
                ),
                .init(
                    name: "order_by",
                    value: "updated_at"
                ),
                .init(name: "sort", value: "desc"),
                .init(name: "per_page", value: "20"),
            ]
        )
    }

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
                    input.dueDate?.apiValue,
                milestoneID:
                    input.milestone?.id
            )
        )
    }

    static func createWithWorkItemFields(
        _ input: GitLabIssueCreationInput
    ) throws -> GitLabAPIRequest<
        GitLabIssueCreateGraphQLResponse
    > {
        try .graphQL(
            requires: .write,
            body:
                GitLabIssueGraphQLBody(
                    query:
                        createIssueMutation,
                    variables:
                        GitLabIssueCreateVariables(
                            projectPath:
                                input.projectPath,
                            title: input.title,
                            description:
                                input
                                .rawDescription
                                .isEmpty
                                ? nil
                                : input
                                    .rawDescription,
                            labels:
                                input
                                .labelNames
                                .isEmpty
                                ? nil
                                : input
                                    .labelNames,
                            assigneeIDs:
                                input
                                .assigneeIDs
                                .isEmpty
                                ? nil
                                : input
                                    .assigneeIDs
                                    .map(
                                        GitLabIssueGlobalID
                                            .user
                                    ),
                            confidential:
                                input.confidential,
                            dueDate:
                                input
                                .dueDate?
                                .apiValue,
                            milestoneID:
                                input
                                .milestone
                                .map {
                                    GitLabIssueGlobalID
                                        .milestone(
                                            $0.id
                                        )
                                },
                            iterationID:
                                input
                                .iteration
                                .map {
                                    GitLabIssueGlobalID
                                        .iteration(
                                            $0.id
                                        )
                                },
                            statusID:
                                input.status?.id
                        )
                )
        )
    }

    private static let createIssueMutation =
        """
        mutation GlabCreateIssue(
          $projectPath: ID!
          $title: String!
          $description: String
          $labels: [String!]
          $assigneeIDs: [UserID!]
          $confidential: Boolean
          $dueDate: ISO8601Date
          $milestoneID: MilestoneID
          $iterationID: IterationID
          $statusID: WorkItemsStatusesStatusID
        ) {
          createIssue(
            input: {
              projectPath: $projectPath
              title: $title
              description: $description
              labels: $labels
              assigneeIds: $assigneeIDs
              confidential: $confidential
              dueDate: $dueDate
              milestoneId: $milestoneID
              iterationId: $iterationID
              statusId: $statusID
            }
          ) {
            issue {
              iid
              projectId
            }
            errors
          }
        }
        """
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
    let milestoneID: Int?

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
        case milestoneID = "milestone_id"
    }
}

private nonisolated struct GitLabIssueCreateVariables:
    Encodable,
    Sendable
{
    let projectPath: String
    let title: String
    let description: String?
    let labels: [String]?
    let assigneeIDs: [String]?
    let confidential: Bool
    let dueDate: String?
    let milestoneID: String?
    let iterationID: String?
    let statusID: String?
}
