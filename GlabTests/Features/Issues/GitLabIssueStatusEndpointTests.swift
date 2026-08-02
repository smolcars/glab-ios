import Foundation
import Testing
@testable import Glab

@Suite("GitLab issue work-item status endpoints")
struct GitLabIssueStatusEndpointTests {
    @Test("Builds the project identity request")
    func buildsProjectIdentityRequest() throws {
        let endpoint =
            GitLabIssueStatusEndpoints.project(
                projectID: 42
            )
        let request = try buildRequest(endpoint)

        #expect(endpoint.method == .get)
        #expect(endpoint.requiredAccess == .read)
        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/api/v4/projects/42"
        )
    }

    @Test("Builds a bounded project and IID status query")
    func buildsStatusQuery() throws {
        let endpoint =
            try GitLabIssueStatusEndpoints.status(
                projectPath: "group/subgroup/project",
                issueIID: 17
            )
        let request = try buildRequest(endpoint)
        let body = try jsonObject(request)
        let variables = try #require(
            body["variables"] as? [String: String]
        )
        let query = try #require(
            body["query"] as? String
        )

        #expect(endpoint.target == .graphQL)
        #expect(endpoint.method == .post)
        #expect(endpoint.requiredAccess == .read)
        #expect(variables["projectPath"] == "group/subgroup/project")
        #expect(variables["iid"] == "17")
        #expect(query.contains("workItems(iids: [$iid], first: 2)"))
        #expect(query.contains("pageInfo"))
        #expect(query.contains("hasNextPage"))
        #expect(query.contains("updateWorkItem"))
        #expect(query.contains("WorkItemWidgetStatus"))
        #expect(query.contains("WorkItemWidgetDefinitionStatus"))
        #expect(query.contains("allowedStatuses"))
    }

    @Test("Builds an exact opaque-ID status mutation")
    func buildsStatusMutation() throws {
        let endpoint =
            try GitLabIssueStatusEndpoints.update(
                workItemID: "gid://example/opaque/work-item?x=1",
                statusID: "gid://example/opaque/status#done"
            )
        let request = try buildRequest(endpoint)
        let body = try jsonObject(request)
        let variables = try #require(
            body["variables"] as? [String: String]
        )
        let query = try #require(
            body["query"] as? String
        )

        #expect(endpoint.target == .graphQL)
        #expect(endpoint.method == .post)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            variables["workItemID"]
                == "gid://example/opaque/work-item?x=1"
        )
        #expect(
            variables["statusID"]
                == "gid://example/opaque/status#done"
        )
        #expect(query.contains("workItemUpdate"))
        #expect(query.contains("statusWidget: { status: $statusID }"))
        #expect(!query.contains("gid://example/opaque"))
    }

    @Test("Maps a complete supported snapshot and deterministic order")
    func mapsSupportedSnapshot() throws {
        let response = try decode(
            statusResponse(
                allowedStatuses: [
                    statusJSON(
                        id: "status-done",
                        name: "Done",
                        position: 1,
                        category: "DONE"
                    ),
                    statusJSON(
                        id: "status-progress-b",
                        name: "Review",
                        position: 2,
                        category: "IN_PROGRESS"
                    ),
                    statusJSON(
                        id: "status-triage",
                        name: "Triage",
                        position: 0,
                        category: "TRIAGE"
                    ),
                    statusJSON(
                        id: "status-todo",
                        name: "To do",
                        position: 0,
                        category: "TO_DO"
                    ),
                    statusJSON(
                        id: "status-progress-a",
                        name: "Building",
                        position: 2,
                        category: "IN_PROGRESS"
                    ),
                    statusJSON(
                        id: "status-canceled",
                        name: "Canceled",
                        position: 0,
                        category: "CANCELED"
                    ),
                ],
                currentStatus:
                    statusJSON(
                        id: "status-progress-a",
                        name: "Building",
                        position: 2,
                        category: "IN_PROGRESS"
                    )
            )
        )
        let snapshot = try #require(
            response.validatedSnapshot(
                projectPath: "group/project",
                issueIID: 17
            )
        )

        #expect(snapshot.workItemID == "opaque-work-item-id")
        #expect(snapshot.issueIID == 17)
        #expect(snapshot.projectPath == "group/project")
        #expect(snapshot.state == .open)
        #expect(snapshot.lockVersion == 8)
        #expect(snapshot.canUpdate)
        #expect(snapshot.currentStatus?.id == "status-progress-a")
        #expect(
            snapshot.allowedStatuses.map(\.category)
                == [
                    .triage,
                    .toDo,
                    .inProgress,
                    .inProgress,
                    .done,
                    .canceled,
                ]
        )
        #expect(
            snapshot.allowedStatuses.map(\.id)
                == [
                    "status-triage",
                    "status-todo",
                    "status-progress-a",
                    "status-progress-b",
                    "status-done",
                    "status-canceled",
                ]
        )
    }

    @Test(
        "Maps every lifecycle category to its issue state",
        arguments: [
            ("TRIAGE", GitLabIssueStateKind.opened),
            ("TO_DO", GitLabIssueStateKind.opened),
            ("IN_PROGRESS", GitLabIssueStateKind.opened),
            ("DONE", GitLabIssueStateKind.closed),
            ("CANCELED", GitLabIssueStateKind.closed),
        ]
    )
    func mapsCategoryState(
        category: String,
        expectedState: GitLabIssueStateKind
    ) throws {
        let status = try #require(
            GitLabIssueStatusCategory(
                rawValue: category
            )
        )

        #expect(status.issueState == expectedState)
    }

    @Test("Accepts lowercase status categories returned by GitLab")
    func mapsLowercaseStatusCategories() throws {
        let response = try decode(
            statusResponse(
                allowedStatuses: [
                    statusJSON(
                        category: "in_progress"
                    ),
                ],
                currentStatus:
                    statusJSON(
                        category: "in_progress"
                    )
            )
        )
        let snapshot = try #require(
            response.validatedSnapshot(
                projectPath: "group/project",
                issueIID: 17
            )
        )

        #expect(
            snapshot.currentStatus?.category
                == .inProgress
        )
        #expect(
            snapshot.allowedStatuses
                .map(\.category)
                == [.inProgress]
        )
    }

    @Test("Allows a missing current status")
    func allowsMissingCurrentStatus() throws {
        let response = try decode(
            statusResponse(
                currentStatus: nil
            )
        )
        let snapshot = try #require(
            response.validatedSnapshot(
                projectPath: "group/project",
                issueIID: 17
            )
        )

        #expect(snapshot.currentStatus == nil)
    }

    @Test("Rejects invalid caller identity")
    func rejectsInvalidCallerIdentity() throws {
        let blankProject = try decode(
            statusResponse(projectPath: " ")
        )
        let validResponse = try decode(
            statusResponse()
        )

        #expect(
            blankProject.validatedSnapshot(
                projectPath: " ",
                issueIID: 17
            ) == nil
        )
        #expect(
            validResponse.validatedSnapshot(
                projectPath: "group/project",
                issueIID: 0
            ) == nil
        )
    }

    @Test(
        "Rejects incompatible or ambiguous snapshots",
        arguments: [
            SnapshotDefect.wrongProject,
            .zeroWorkItems,
            .multipleWorkItems,
            .unexpectedNextPage,
            .wrongIID,
            .wrongType,
            .blankWorkItemID,
            .negativeLockVersion,
            .missingStatusWidget,
            .missingStatusDefinition,
            .emptyAllowedStatuses,
            .duplicateAllowedStatusID,
            .blankStatusName,
            .unknownCategory,
            .negativePosition,
            .currentStatusNotAllowed,
            .stateCategoryMismatch,
        ]
    )
    fileprivate func rejectsInvalidSnapshots(
        defect: SnapshotDefect
    ) throws {
        let response = try decode(
            defectiveStatusResponse(defect)
        )

        #expect(
            response.validatedSnapshot(
                projectPath: "group/project",
                issueIID: 17
            ) == nil
        )
    }

    @Test("Decodes top-level GraphQL errors without throwing")
    func decodesTopLevelErrors() throws {
        let response = try decode(
            """
            {
              "data": {"project": null},
              "errors": [
                {
                  "message": "Field unavailable",
                  "path": ["project", "workItems"]
                }
              ]
            }
            """
        )

        #expect(response.errors?.map(\.message) == ["Field unavailable"])
        #expect(
            response.validatedSnapshot(
                projectPath: "group/project",
                issueIID: 17
            ) == nil
        )
    }

    @Test("Validates an authoritative mutation result")
    func validatesMutationResult() throws {
        let selectedStatus =
            GitLabIssueWorkItemStatus(
                id: "status-done",
                name: "Done",
                description: "Optional hint",
                iconName: "status-running",
                color: "#1F75CB",
                position: 2,
                category: .done
            )
        let response = try decodeUpdate(
            updateResponse()
        )
        let result = try #require(
            response.validatedResult(
                workItemID: "opaque-work-item-id",
                issueIID: 17,
                selectedStatus: selectedStatus,
                baselineState: .open,
                baselineLockVersion: 8
            )
        )

        #expect(result.workItemID == "opaque-work-item-id")
        #expect(result.issueIID == 17)
        #expect(result.state == .closed)
        #expect(result.lockVersion == 9)
        #expect(result.status.id == "status-done")
    }

    @Test(
        "Accepts a same-state status update with an unchanged lock version"
    )
    func validatesUnchangedMutationLockVersion() throws {
        let selectedStatus =
            GitLabIssueWorkItemStatus(
                id: "status-review",
                name: "Review",
                description: "Optional hint",
                iconName: "status-running",
                color: "#1F75CB",
                position: 2,
                category: .inProgress
            )
        let response = try decodeUpdate(
            updateResponse(
                state: "OPEN",
                lockVersion: 8,
                statusID: "status-review",
                statusCategory: "IN_PROGRESS"
            )
        )
        let result = try #require(
            response.validatedResult(
                workItemID: "opaque-work-item-id",
                issueIID: 17,
                selectedStatus: selectedStatus,
                baselineState: .open,
                baselineLockVersion: 8
            )
        )

        #expect(result.lockVersion == 8)
        #expect(result.status.id == "status-review")
    }

    @Test(
        "Rejects ambiguous or unverifiable mutation responses",
        arguments: [
            UpdateDefect.topLevelError,
            .payloadError,
            .missingPayload,
            .wrongWorkItemID,
            .wrongIID,
            .wrongType,
            .wrongStatus,
            .stateCategoryMismatch,
            .unadvancedStateTransition,
            .regressedLockVersion,
        ]
    )
    fileprivate func rejectsInvalidMutation(
        defect: UpdateDefect
    ) throws {
        let response = try decodeUpdate(
            defectiveUpdateResponse(defect)
        )
        let selectedStatus =
            GitLabIssueWorkItemStatus(
                id: "status-done",
                name: "Done",
                description: "Optional hint",
                iconName: "status-running",
                color: "#1F75CB",
                position: 2,
                category: .done
            )

        #expect(
            response.validatedResult(
                workItemID: "opaque-work-item-id",
                issueIID: 17,
                selectedStatus: selectedStatus,
                baselineState: .open,
                baselineLockVersion: 8
            ) == nil
        )
    }

    @Test("Rejects an invalid expected mutation identity")
    func rejectsInvalidExpectedMutationIdentity() throws {
        let response = try decodeUpdate(
            updateResponse(
                workItemID: " "
            )
        )
        let selectedStatus =
            GitLabIssueWorkItemStatus(
                id: "status-done",
                name: "Done",
                description: nil,
                iconName: nil,
                color: nil,
                position: 2,
                category: .done
            )

        #expect(
            response.validatedResult(
                workItemID: " ",
                issueIID: 17,
                selectedStatus: selectedStatus,
                baselineState: .open,
                baselineLockVersion: 8
            ) == nil
        )
    }
}

private extension GitLabIssueStatusEndpointTests {
    nonisolated enum SnapshotDefect: CaseIterable, Sendable {
        case wrongProject
        case zeroWorkItems
        case multipleWorkItems
        case unexpectedNextPage
        case wrongIID
        case wrongType
        case blankWorkItemID
        case negativeLockVersion
        case missingStatusWidget
        case missingStatusDefinition
        case emptyAllowedStatuses
        case duplicateAllowedStatusID
        case blankStatusName
        case unknownCategory
        case negativePosition
        case currentStatusNotAllowed
        case stateCategoryMismatch
    }

    nonisolated enum UpdateDefect: CaseIterable, Sendable {
        case topLevelError
        case payloadError
        case missingPayload
        case wrongWorkItemID
        case wrongIID
        case wrongType
        case wrongStatus
        case stateCategoryMismatch
        case unadvancedStateTransition
        case regressedLockVersion
    }

    nonisolated func buildRequest<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URLRequest {
        try GitLabRequestBuilder(
            host: GitLabHost("gitlab.example.com"),
            authorization:
                .personalAccessToken("pat-secret")
        ).build(endpoint)
    }

    nonisolated func jsonObject(
        _ request: URLRequest
    ) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(
            JSONSerialization.jsonObject(
                with: body
            ) as? [String: Any]
        )
    }

    nonisolated func decode(
        _ json: String
    ) throws -> GitLabIssueStatusGraphQLResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            GitLabIssueStatusGraphQLResponse.self,
            from: Data(json.utf8)
        )
    }

    nonisolated func decodeUpdate(
        _ json: String
    ) throws -> GitLabIssueStatusUpdateGraphQLResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            GitLabIssueStatusUpdateGraphQLResponse.self,
            from: Data(json.utf8)
        )
    }

    nonisolated func statusJSON(
        id: String = "status-progress",
        name: String = "In progress",
        position: Int = 1,
        category: String = "IN_PROGRESS"
    ) -> String {
        """
        {
          "id": "\(id)",
          "name": "\(name)",
          "description": "Optional hint",
          "iconName": "status-running",
          "color": "#1F75CB",
          "position": \(position),
          "category": "\(category)"
        }
        """
    }

    nonisolated func statusResponse(
        projectPath: String = "group/project",
        nodes: String? = nil,
        hasNextPage: Bool = false,
        workItemID: String = "opaque-work-item-id",
        issueIID: String = "17",
        state: String = "OPEN",
        lockVersion: Int = 8,
        workItemType: String = "Issue",
        includeStatusWidget: Bool = true,
        includeStatusDefinition: Bool = true,
        allowedStatuses: [String]? = nil,
        currentStatus: String? = "default"
    ) -> String {
        let allowed =
            allowedStatuses
            ?? [
                statusJSON(),
                statusJSON(
                    id: "status-done",
                    name: "Done",
                    position: 2,
                    category: "DONE"
                ),
            ]
        let current =
            currentStatus == "default"
            ? statusJSON()
            : currentStatus
        let widget =
            includeStatusWidget
            ? """
              {
                "__typename": "WorkItemWidgetStatus",
                "status": \(current ?? "null")
              }
            """
            : """
              {"__typename": "WorkItemWidgetDescription"}
            """
        let definition =
            includeStatusDefinition
            ? """
              {
                "__typename": "WorkItemWidgetDefinitionStatus",
                "allowedStatuses": [\(allowed.joined(separator: ","))]
              }
            """
            : """
              {"__typename": "WorkItemWidgetDefinitionDescription"}
            """
        let defaultNode =
            """
            {
              "id": "\(workItemID)",
              "iid": "\(issueIID)",
              "state": "\(state)",
              "updatedAt": "2026-07-28T12:00:00Z",
              "lockVersion": \(lockVersion),
              "webUrl": "https://gitlab.example.com/group/project/-/issues/17",
              "userPermissions": {"updateWorkItem": true},
              "workItemType": {
                "name": "\(workItemType)",
                "widgetDefinitions": [\(definition)]
              },
              "widgets": [\(widget)]
            }
            """

        return """
        {
          "data": {
            "project": {
              "fullPath": "\(projectPath)",
              "workItems": {
                "nodes": [\(nodes ?? defaultNode)],
                "pageInfo": {"hasNextPage": \(hasNextPage)}
              }
            }
          }
        }
        """
    }

    nonisolated func defectiveStatusResponse(
        _ defect: SnapshotDefect
    ) -> String {
        switch defect {
        case .wrongProject:
            statusResponse(projectPath: "other/project")
        case .zeroWorkItems:
            statusResponse(nodes: "")
        case .multipleWorkItems:
            statusResponse(
                nodes:
                    """
                    {"id":"one"},
                    {"id":"two"}
                    """
            )
        case .unexpectedNextPage:
            statusResponse(hasNextPage: true)
        case .wrongIID:
            statusResponse(issueIID: "18")
        case .wrongType:
            statusResponse(workItemType: "Task")
        case .blankWorkItemID:
            statusResponse(workItemID: "  ")
        case .negativeLockVersion:
            statusResponse(lockVersion: -1)
        case .missingStatusWidget:
            statusResponse(includeStatusWidget: false)
        case .missingStatusDefinition:
            statusResponse(includeStatusDefinition: false)
        case .emptyAllowedStatuses:
            statusResponse(allowedStatuses: [])
        case .duplicateAllowedStatusID:
            statusResponse(
                allowedStatuses: [
                    statusJSON(),
                    statusJSON(
                        name: "Duplicate"
                    ),
                ]
            )
        case .blankStatusName:
            statusResponse(
                allowedStatuses: [
                    statusJSON(name: "  "),
                ],
                currentStatus:
                    statusJSON(name: "  ")
            )
        case .unknownCategory:
            statusResponse(
                allowedStatuses: [
                    statusJSON(category: "FUTURE"),
                ],
                currentStatus:
                    statusJSON(category: "FUTURE")
            )
        case .negativePosition:
            statusResponse(
                allowedStatuses: [
                    statusJSON(position: -1),
                ],
                currentStatus:
                    statusJSON(position: -1)
            )
        case .currentStatusNotAllowed:
            statusResponse(
                currentStatus:
                    statusJSON(
                        id: "another-status"
                    )
            )
        case .stateCategoryMismatch:
            statusResponse(state: "CLOSED")
        }
    }

    nonisolated func updateResponse(
        workItemID: String = "opaque-work-item-id",
        issueIID: String = "17",
        state: String = "CLOSED",
        lockVersion: Int = 9,
        workItemType: String = "Issue",
        statusID: String = "status-done",
        statusCategory: String = "DONE",
        payloadErrors: String = "[]"
    ) -> String {
        """
        {
          "data": {
            "workItemUpdate": {
              "workItem": {
                "id": "\(workItemID)",
                "iid": "\(issueIID)",
                "state": "\(state)",
                "updatedAt": "2026-07-28T12:05:00Z",
                "lockVersion": \(lockVersion),
                "workItemType": {"name": "\(workItemType)"},
                "widgets": [
                  {
                    "__typename": "WorkItemWidgetStatus",
                    "status": \(statusJSON(
                        id: statusID,
                        name: statusID == "status-done"
                            ? "Done"
                            : "Other",
                        position: 2,
                        category: statusCategory
                    ))
                  }
                ]
              },
              "errors": \(payloadErrors)
            }
          }
        }
        """
    }

    nonisolated func defectiveUpdateResponse(
        _ defect: UpdateDefect
    ) -> String {
        switch defect {
        case .topLevelError:
            """
            {
              "data": {"workItemUpdate": null},
              "errors": [{"message": "Denied"}]
            }
            """
        case .payloadError:
            updateResponse(
                payloadErrors: "[\"Status is unavailable\"]"
            )
        case .missingPayload:
            """
            {"data":{"workItemUpdate":null}}
            """
        case .wrongWorkItemID:
            updateResponse(workItemID: "other-work-item")
        case .wrongIID:
            updateResponse(issueIID: "18")
        case .wrongType:
            updateResponse(workItemType: "Task")
        case .wrongStatus:
            updateResponse(statusID: "another-status")
        case .stateCategoryMismatch:
            updateResponse(state: "OPEN")
        case .unadvancedStateTransition:
            updateResponse(lockVersion: 8)
        case .regressedLockVersion:
            updateResponse(lockVersion: 7)
        }
    }
}
