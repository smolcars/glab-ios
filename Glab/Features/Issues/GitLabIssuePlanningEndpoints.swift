import Foundation

nonisolated enum GitLabIssuePlanningEndpoints {
    static func planning(
        projectPath: String,
        issueIID: Int
    ) throws -> GitLabAPIRequest<
        GitLabIssuePlanningGraphQLResponse
    > {
        try .graphQL(
            requires: .read,
            body:
                GitLabIssueGraphQLBody(
                    query: planningQuery,
                    variables:
                        GitLabIssuePlanningQueryVariables(
                            projectPath:
                                projectPath,
                            iid:
                                String(issueIID)
                        )
                )
        )
    }

    static func update(
        workItemID: String,
        change:
            GitLabIssuePlanningChange
    ) throws -> GitLabAPIRequest<
        GitLabIssuePlanningUpdateGraphQLResponse
    > {
        switch change {
        case let .milestone(id):
            try .graphQL(
                requires: .write,
                body:
                    GitLabIssueGraphQLBody(
                        query:
                            updateMilestoneMutation,
                        variables:
                            GitLabIssuePlanningMilestoneVariables(
                                workItemID:
                                    workItemID,
                                milestoneID:
                                    id.map(
                                        GitLabIssueGlobalID
                                            .milestone
                                    )
                            )
                    )
            )
        case let .iteration(id):
            try .graphQL(
                requires: .write,
                body:
                    GitLabIssueGraphQLBody(
                        query:
                            updateIterationMutation,
                        variables:
                            GitLabIssuePlanningIterationVariables(
                                workItemID:
                                    workItemID,
                                iterationID:
                                    id.map(
                                        GitLabIssueGlobalID
                                            .iteration
                                    )
                            )
                    )
            )
        }
    }

    private static let planningQuery =
        """
        query GlabIssuePlanning($projectPath: ID!, $iid: String!) {
          project(fullPath: $projectPath) {
            fullPath
            workItems(iids: [$iid], first: 2) {
              nodes {
                id
                iid
                userPermissions {
                  updateWorkItem
                }
                workItemType {
                  name
                }
                widgets {
                  __typename
                  ... on WorkItemWidgetMilestone {
                    milestone {
                      id
                    }
                  }
                  ... on WorkItemWidgetIteration {
                    iteration {
                      id
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

    private static let updateMilestoneMutation =
        """
        mutation GlabUpdateIssueMilestone(
          $workItemID: WorkItemID!
          $milestoneID: MilestoneID
        ) {
          workItemUpdate(
            input: {
              id: $workItemID
              milestoneWidget: {
                milestoneId: $milestoneID
              }
            }
          ) {
            workItem {
              id
              iid
              workItemType {
                name
              }
              widgets {
                __typename
                ... on WorkItemWidgetMilestone {
                  milestone {
                    id
                  }
                }
                ... on WorkItemWidgetIteration {
                  iteration {
                    id
                  }
                }
              }
            }
            errors
          }
        }
        """

    private static let updateIterationMutation =
        """
        mutation GlabUpdateIssueIteration(
          $workItemID: WorkItemID!
          $iterationID: IterationID
        ) {
          workItemUpdate(
            input: {
              id: $workItemID
              iterationWidget: {
                iterationId: $iterationID
              }
            }
          ) {
            workItem {
              id
              iid
              workItemType {
                name
              }
              widgets {
                __typename
                ... on WorkItemWidgetMilestone {
                  milestone {
                    id
                  }
                }
                ... on WorkItemWidgetIteration {
                  iteration {
                    id
                  }
                }
              }
            }
            errors
          }
        }
        """
}

private nonisolated struct GitLabIssuePlanningQueryVariables:
    Encodable,
    Sendable
{
    let projectPath: String
    let iid: String
}

private nonisolated struct GitLabIssuePlanningMilestoneVariables:
    Encodable,
    Sendable
{
    let workItemID: String
    let milestoneID: String?
}

private nonisolated struct GitLabIssuePlanningIterationVariables:
    Encodable,
    Sendable
{
    let workItemID: String
    let iterationID: String?
}
