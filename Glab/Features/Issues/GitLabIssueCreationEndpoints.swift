import Foundation

nonisolated enum GitLabIssueCreationEndpoints {
    static func milestones(
        projectID: Int
    ) -> GitLabAPIRequest<
        [GitLabIssueMilestone]
    > {
        .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "milestones",
            ],
            query: [
                .init(
                    name: "state",
                    value: "active"
                ),
                .init(
                    name: "include_ancestors",
                    value: "true"
                ),
                .init(
                    name: "per_page",
                    value: "100"
                ),
            ]
        )
    }

    static func iterations(
        projectID: Int
    ) -> GitLabAPIRequest<
        [GitLabIssueIteration]
    > {
        .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "iterations",
            ],
            query: [
                .init(
                    name: "state",
                    value: "opened"
                ),
                .init(
                    name: "include_ancestors",
                    value: "true"
                ),
                .init(
                    name: "per_page",
                    value: "100"
                ),
            ]
        )
    }

    static func statuses(
        projectPath: String
    ) throws -> GitLabAPIRequest<
        GitLabIssueCreationStatusGraphQLResponse
    > {
        try .graphQL(
            requires: .read,
            body:
                GitLabIssueGraphQLBody(
                    query: statusesQuery,
                    variables:
                        StatusVariables(
                            projectPath:
                                projectPath
                        )
                )
        )
    }

    static func labels(
        projectID: Int,
        search: String? = nil
    ) -> GitLabAPIRequest<[GitLabProjectLabel]> {
        .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "labels",
            ],
            query: [
                .init(
                    name: "with_counts",
                    value: "false"
                ),
                .init(
                    name: "include_ancestor_groups",
                    value: "true"
                ),
                .init(
                    name: "per_page",
                    value: "20"
                ),
            ] + searchQuery(
                name: "search",
                value: search
            )
        )
    }

    private static func searchQuery(
        name: String,
        value: String?
    ) -> [URLQueryItem] {
        let normalized =
            value?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard
            let normalized,
            !normalized.isEmpty
        else {
            return []
        }
        return [
            URLQueryItem(
                name: name,
                value: normalized
            ),
        ]
    }

    private struct StatusVariables:
        Encodable,
        Sendable
    {
        let projectPath: String
    }

    private static let statusesQuery =
        """
        query GlabIssueCreationStatuses($projectPath: ID!) {
          project(fullPath: $projectPath) {
            fullPath
            workItemTypes(name: ISSUE, first: 2) {
              nodes {
                name
                widgetDefinitions {
                  __typename
                  ... on WorkItemWidgetDefinitionStatus {
                    allowedStatuses {
                      id
                      name
                      description
                      iconName
                      color
                      position
                      category
                    }
                  }
                }
              }
              pageInfo {
                hasNextPage
              }
            }
          }
        }
        """
}
