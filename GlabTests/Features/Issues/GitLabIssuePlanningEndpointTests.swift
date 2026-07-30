import Foundation
import Testing
@testable import Glab

@Suite("GitLab issue planning endpoints")
struct GitLabIssuePlanningEndpointTests {
    @Test("Builds the planning query")
    func buildsPlanningQuery() throws {
        let endpoint =
            try GitLabIssuePlanningEndpoints
                .planning(
                    projectPath:
                        "group/project",
                    issueIID: 7
                )
        let json = try jsonObject(
            buildRequest(endpoint)
        )
        let variables = try #require(
            json["variables"]
                as? [String: String]
        )

        #expect(endpoint.requiredAccess == .read)
        #expect(
            variables
                == [
                    "projectPath":
                        "group/project",
                    "iid": "7",
                ]
        )
        #expect(
            (json["query"] as? String)?
                .contains(
                    "WorkItemWidgetIteration"
                ) == true
        )
        #expect(
            (json["query"] as? String)?
                .contains(
                    "WorkItemWidgetMilestone"
                ) == true
        )
    }

    @Test("Builds nullable milestone and iteration mutations")
    func buildsPlanningMutations() throws {
        let milestone =
            try GitLabIssuePlanningEndpoints
                .update(
                    workItemID:
                        "gid://gitlab/WorkItem/101",
                    change:
                        .milestone(19)
                )
        let iteration =
            try GitLabIssuePlanningEndpoints
                .update(
                    workItemID:
                        "gid://gitlab/WorkItem/101",
                    change:
                        .iteration(nil)
                )
        let milestoneJSON =
            try jsonObject(
                buildRequest(milestone)
            )
        let milestoneVariables =
            try #require(
                milestoneJSON["variables"]
                    as? [String: String]
            )
        let iterationJSON =
            try jsonObject(
                buildRequest(iteration)
            )
        let iterationVariables =
            try #require(
                iterationJSON["variables"]
                    as? [String: String]
            )

        #expect(
            milestoneVariables[
                "milestoneID"
            ] == "gid://gitlab/Milestone/19"
        )
        #expect(
            milestoneVariables[
                "workItemID"
            ] == "gid://gitlab/WorkItem/101"
        )
        #expect(
            iterationVariables[
                "iterationID"
            ] == nil
        )
        #expect(
            (iterationJSON["query"] as? String)?
                .contains(
                    "iterationWidget"
                ) == true
        )
    }

    @Test("Validates a unique issue planning snapshot")
    func validatesPlanningSnapshot() throws {
        let response =
            try JSONDecoder().decode(
                GitLabIssuePlanningGraphQLResponse
                    .self,
                from:
                    Data(
                        planningJSON.utf8
                    )
            )
        let snapshot =
            response.validatedSnapshot(
                projectPath:
                    "group/project",
                issueIID: 7
            )

        #expect(
            snapshot
                == GitLabIssuePlanningSnapshot(
                    projectPath:
                        "group/project",
                    workItemID:
                        "gid://gitlab/WorkItem/101",
                    issueIID: 7,
                    milestoneID: 19,
                    iterationID: 23,
                    canUpdate: true
                )
        )
    }

    @Test("Validates an iteration removal result")
    func validatesIterationRemoval() throws {
        let baseline =
            GitLabIssuePlanningSnapshot(
                projectPath:
                    "group/project",
                workItemID:
                    "gid://gitlab/WorkItem/101",
                issueIID: 7,
                milestoneID: 19,
                iterationID: 23,
                canUpdate: true
            )
        let response =
            try JSONDecoder().decode(
                GitLabIssuePlanningUpdateGraphQLResponse
                    .self,
                from:
                    Data(
                        updateJSON.utf8
                    )
            )

        #expect(
            response.validatedSnapshot(
                baseline: baseline,
                change: .iteration(nil)
            )
                == baseline.applying(
                    .iteration(nil)
                )
        )
    }
}

private extension GitLabIssuePlanningEndpointTests {
    nonisolated func buildRequest<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URLRequest {
        try GitLabRequestBuilder(
            host:
                GitLabHost(
                    "gitlab.example.com"
                ),
            authorization:
                .personalAccessToken(
                    "pat-secret"
                )
        ).build(endpoint)
    }

    nonisolated func jsonObject(
        _ request: URLRequest
    ) throws -> [String: Any] {
        let body = try #require(
            request.httpBody
        )
        return try #require(
            JSONSerialization.jsonObject(
                with: body
            ) as? [String: Any]
        )
    }

    nonisolated var planningJSON: String {
        """
        {
          "data": {
            "project": {
              "fullPath": "group/project",
              "workItems": {
                "nodes": [{
                  "id": "gid://gitlab/WorkItem/101",
                  "iid": "7",
                  "userPermissions": {
                    "updateWorkItem": true
                  },
                  "workItemType": {
                    "name": "Issue"
                  },
                  "widgets": [{
                    "__typename": "WorkItemWidgetMilestone",
                    "milestone": {
                      "id": "gid://gitlab/Milestone/19"
                    }
                  }, {
                    "__typename": "WorkItemWidgetIteration",
                    "iteration": {
                      "id": "gid://gitlab/Iteration/23"
                    }
                  }]
                }],
                "pageInfo": {
                  "hasNextPage": false
                }
              }
            }
          }
        }
        """
    }

    nonisolated var updateJSON: String {
        """
        {
          "data": {
            "workItemUpdate": {
              "workItem": {
                "id": "gid://gitlab/WorkItem/101",
                "iid": "7",
                "workItemType": {
                  "name": "Issue"
                },
                "widgets": [{
                  "__typename": "WorkItemWidgetMilestone",
                  "milestone": {
                    "id": "gid://gitlab/Milestone/19"
                  }
                }, {
                  "__typename": "WorkItemWidgetIteration",
                  "iteration": null
                }]
              },
              "errors": []
            }
          }
        }
        """
    }
}
