import Foundation

nonisolated enum GitLabIssueStatusEndpoints {
    static func project(
        projectID: Int
    ) -> GitLabAPIRequest<GitLabProject> {
        .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
            ]
        )
    }

    static func status(
        projectPath: String,
        issueIID: Int
    ) throws -> GitLabAPIRequest<
        GitLabIssueStatusGraphQLResponse
    > {
        try .graphQL(
            requires: .read,
            body:
                GraphQLBody(
                    query: statusQuery,
                    variables: [
                        "projectPath": projectPath,
                        "iid": String(issueIID),
                    ]
                )
        )
    }

    static func update(
        workItemID: String,
        statusID: String
    ) throws -> GitLabAPIRequest<
        GitLabIssueStatusUpdateGraphQLResponse
    > {
        try .graphQL(
            requires: .write,
            body:
                GraphQLBody(
                    query: updateMutation,
                    variables: [
                        "workItemID": workItemID,
                        "statusID": statusID,
                    ]
                )
        )
    }

    private static let statusQuery =
        """
        query GlabIssueStatus($projectPath: ID!, $iid: String!) {
          project(fullPath: $projectPath) {
            fullPath
            workItems(iids: [$iid], first: 2) {
              nodes {
                id
                iid
                state
                updatedAt
                lockVersion
                webUrl
                userPermissions {
                  updateWorkItem
                }
                workItemType {
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
                widgets {
                  __typename
                  ... on WorkItemWidgetStatus {
                    status {
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

    private static let updateMutation =
        """
        mutation GlabUpdateIssueStatus(
          $workItemID: WorkItemID!
          $statusID: WorkItemsStatusesStatusID!
        ) {
          workItemUpdate(
            input: {
              id: $workItemID
              statusWidget: { status: $statusID }
            }
          ) {
            workItem {
              id
              iid
              state
              updatedAt
              lockVersion
              workItemType {
                name
              }
              widgets {
                __typename
                ... on WorkItemWidgetStatus {
                  status {
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
            errors
          }
        }
        """
}

private nonisolated struct GraphQLBody:
    Encodable,
    Sendable
{
    let query: String
    let variables: [String: String]
}
