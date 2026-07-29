import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab issue status service")
struct LiveGitLabIssueStatusServiceTests {
    @Test("Resolves the project once and loads a supported snapshot")
    func resolvesProjectAndLoadsStatus() async throws {
        let client = RecordingIssueStatusClient()
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readWrite
            )

        let result = try await service.loadStatus(
            for: makeTestIssue(
                iid: 17
            )
        )

        guard case let .supported(snapshot) = result else {
            Issue.record("Expected a supported status snapshot.")
            return
        }
        #expect(snapshot.projectPath == "group/project")
        #expect(snapshot.issueIID == 17)
        #expect(snapshot.currentStatus?.id == "status-progress")
        #expect(
            await client.sentKinds
                == [.project, .statusQuery]
        )
        #expect(
            await client.sentAccess
                == [.read, .read]
        )
    }

    @Test("Refresh reuses the validated project path")
    func refreshReusesProjectPath() async throws {
        let client = RecordingIssueStatusClient()
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readWrite
            )

        let result = try await service.refreshStatus(
            projectPath: "group/project",
            issueIID: 17
        )

        #expect(
            result
                == .supported(
                    makeStatusSnapshot()
                )
        )
        #expect(
            await client.sentKinds
                == [.statusQuery]
        )
    }

    @Test(
        "Invalid project identity makes the enhancement unavailable",
        arguments: [
            makeTestProject(
                id: 99,
                pathWithNamespace: "group/project"
            ),
            makeTestProject(
                id: 42,
                pathWithNamespace: " "
            ),
        ]
    )
    func rejectsInvalidProjectIdentity(
        project: GitLabProject
    ) async throws {
        let client =
            RecordingIssueStatusClient(
                project: project
            )
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readWrite
            )

        let result = try await service.loadStatus(
            for: makeTestIssue(
                iid: 17
            )
        )

        #expect(result == .unavailable)
        #expect(
            await client.sentKinds
                == [.project]
        )
    }

    @Test("Invalid REST issue identity sends no request")
    func rejectsInvalidIssueIdentity() async throws {
        let client = RecordingIssueStatusClient()
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readWrite
            )

        let result = try await service.loadStatus(
            for: makeTestIssue(
                iid: 0,
                projectID: 0
            )
        )

        #expect(result == .unavailable)
        #expect(await client.sentKinds.isEmpty)
    }

    @Test("Server permission false remains supported and read-only")
    func supportsReadOnlyPermission() async throws {
        let response = try decodeStatusResponse(
            supportedStatusResponseJSON
                .replacingOccurrences(
                    of:
                        "\"updateWorkItem\": true",
                    with:
                        "\"updateWorkItem\": false"
                )
        )
        let client =
            RecordingIssueStatusClient(
                statusResponse: response
            )
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readOnly
            )

        let result = try await service.loadStatus(
            for: makeTestIssue(
                iid: 17
            )
        )

        guard case let .supported(snapshot) = result else {
            Issue.record("Expected a supported status snapshot.")
            return
        }
        #expect(!snapshot.canUpdate)
    }

    @Test("Incompatible GraphQL data is optional feature absence")
    func incompatibleGraphQLIsUnavailable() async throws {
        let client =
            RecordingIssueStatusClient(
                statusResponse:
                    try decodeStatusResponse(
                        """
                        {
                          "data": {"project": null},
                          "errors": [
                            {"message": "Unknown field allowedStatuses"}
                          ]
                        }
                        """
                    )
            )
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readWrite
            )

        let result = try await service.loadStatus(
            for: makeTestIssue(
                iid: 17
            )
        )

        #expect(result == .unavailable)
    }

    @Test("Authentication failures remain actionable")
    func preservesAuthenticationFailure() async {
        let failure =
            GitLabSessionClientError
                .api(.unauthenticated)
        let client =
            RecordingIssueStatusClient(
                statusFailure: failure
            )
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readWrite
            )

        await #expect(throws: failure) {
            try await service.loadStatus(
                for: makeTestIssue(
                    iid: 17
                )
            )
        }
        #expect(
            await client.sentKinds
                == [.project, .statusQuery]
        )
    }

    @Test("Read-only access rejects a mutation before transport")
    func readOnlyRejectsMutationLocally() async {
        let client = RecordingIssueStatusClient()
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readOnly
            )

        await #expect(
            throws:
                GitLabSessionClientError
                    .insufficientAccess(
                        required: .write
                    )
        ) {
            try await service.updateStatus(
                from: makeStatusSnapshot(),
                to: makeDoneStatus()
            )
        }

        #expect(await client.sentKinds.isEmpty)
    }

    @Test("GitLab permission rejection sends no mutation")
    func permissionRejectsMutationLocally() async throws {
        let client = RecordingIssueStatusClient()
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readWrite
            )
        let outcome = try await service.updateStatus(
            from:
                makeStatusSnapshot(
                    canUpdate: false
                ),
            to: makeDoneStatus()
        )

        #expect(outcome == .rejected)
        #expect(await client.sentKinds.isEmpty)
    }

    @Test("Sends one mutation and validates its result")
    func updatesOnce() async throws {
        let client = RecordingIssueStatusClient()
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readWrite
            )

        let outcome = try await service.updateStatus(
            from: makeStatusSnapshot(),
            to: makeDoneStatus()
        )

        #expect(
            outcome
                == .updated(
                    makeStatusUpdateResult()
                )
        )
        #expect(
            await client.sentKinds
                == [.statusMutation]
        )
        #expect(
            await client.sentAccess
                == [.write]
        )
    }

    @Test("Payload rejection without a work item is definite")
    func classifiesPayloadRejection() async throws {
        let response = try decodeUpdateResponse(
            """
            {
              "data": {
                "workItemUpdate": {
                  "workItem": null,
                  "errors": ["Status is no longer allowed"]
                }
              }
            }
            """
        )
        let client =
            RecordingIssueStatusClient(
                updateResponse: response
            )
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readWrite
            )

        let outcome = try await service.updateStatus(
            from: makeStatusSnapshot(),
            to: makeDoneStatus()
        )

        #expect(outcome == .rejected)
        #expect(
            await client.sentKinds
                == [.statusMutation]
        )
    }

    @Test(
        "Ambiguous GraphQL mutation responses retain unknown delivery",
        arguments: [
            """
            {
              "data": {"workItemUpdate": null},
              "errors": [{"message": "Resolver failed"}]
            }
            """,
            """
            {
              "data": {
                "workItemUpdate": {
                  "workItem": {
                    "id": "opaque-work-item-id",
                    "iid": "17"
                  },
                  "errors": ["Partial mutation"]
                }
              }
            }
            """,
            """
            {
              "data": {
                "workItemUpdate": {
                  "workItem": null,
                  "errors": []
                }
              }
            }
            """,
        ]
    )
    func classifiesAmbiguousResponse(
        json: String
    ) async throws {
        let client =
            RecordingIssueStatusClient(
                updateResponse:
                    try decodeUpdateResponse(
                        json
                    )
            )
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readWrite
            )

        let outcome = try await service.updateStatus(
            from: makeStatusSnapshot(),
            to: makeDoneStatus()
        )

        #expect(outcome == .deliveryUnknown)
        #expect(
            await client.sentKinds
                == [.statusMutation]
        )
    }

    @Test("Mutation transport failure is sent only once")
    func mutationFailureIsNotRepeated() async {
        let failure =
            GitLabSessionClientError
                .api(
                    .connectivity(
                        .networkConnectionLost
                    )
                )
        let client =
            RecordingIssueStatusClient(
                updateFailure: failure
            )
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readWrite
            )

        await #expect(throws: failure) {
            try await service.updateStatus(
                from: makeStatusSnapshot(),
                to: makeDoneStatus()
            )
        }

        #expect(
            await client.sentKinds
                == [.statusMutation]
        )
    }

    @Test("Pre-cancelled work sends no request")
    func cancellationPreventsRequest() async {
        let client = RecordingIssueStatusClient()
        let service =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess: .readWrite
            )
        let task = Task {
            withUnsafeCurrentTask {
                $0?.cancel()
            }
            return try await service.refreshStatus(
                projectPath: "group/project",
                issueIID: 17
            )
        }

        await #expect(
            throws:
                GitLabSessionClientError
                    .api(.cancelled)
        ) {
            try await task.value
        }
        #expect(await client.sentKinds.isEmpty)
    }
}

private nonisolated enum IssueStatusRequestKind:
    Equatable,
    Sendable
{
    case project
    case statusQuery
    case statusMutation
}

private actor RecordingIssueStatusClient:
    GitLabSessionRequestSending
{
    let project: GitLabProject
    let statusResponse:
        GitLabIssueStatusGraphQLResponse
    let updateResponse:
        GitLabIssueStatusUpdateGraphQLResponse
    let projectFailure:
        GitLabSessionClientError?
    let statusFailure:
        GitLabSessionClientError?
    let updateFailure:
        GitLabSessionClientError?

    private(set) var sentKinds:
        [IssueStatusRequestKind] = []
    private(set) var sentAccess:
        [GitLabAPIRequestAccess] = []

    init(
        project: GitLabProject = makeTestProject(
            pathWithNamespace: "group/project"
        ),
        statusResponse:
            GitLabIssueStatusGraphQLResponse =
                try! decodeStatusResponse(
                    supportedStatusResponseJSON
                ),
        updateResponse:
            GitLabIssueStatusUpdateGraphQLResponse =
                try! decodeUpdateResponse(
                    successfulUpdateResponseJSON
                ),
        projectFailure:
            GitLabSessionClientError? = nil,
        statusFailure:
            GitLabSessionClientError? = nil,
        updateFailure:
            GitLabSessionClientError? = nil
    ) {
        self.project = project
        self.statusResponse = statusResponse
        self.updateResponse = updateResponse
        self.projectFailure = projectFailure
        self.statusFailure = statusFailure
        self.updateFailure = updateFailure
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        sentAccess.append(
            endpoint.requiredAccess
        )

        if Response.self == GitLabProject.self {
            sentKinds.append(.project)
            if let projectFailure {
                throw projectFailure
            }
            return project as! Response
        }
        if Response.self
            == GitLabIssueStatusGraphQLResponse
                .self
        {
            sentKinds.append(.statusQuery)
            if let statusFailure {
                throw statusFailure
            }
            return statusResponse as! Response
        }
        if Response.self
            == GitLabIssueStatusUpdateGraphQLResponse
                .self
        {
            sentKinds.append(.statusMutation)
            if let updateFailure {
                throw updateFailure
            }
            return updateResponse as! Response
        }
        throw .api(.invalidResponse)
    }
}

nonisolated func makeStatusSnapshot(
    state: GitLabWorkItemState = .open,
    lockVersion: Int = 8,
    currentStatus:
        GitLabIssueWorkItemStatus? =
            GitLabIssueWorkItemStatus(
                id: "status-progress",
                name: "In progress",
                description: nil,
                iconName: nil,
                color: nil,
                position: 1,
                category: .inProgress
            ),
    allowedStatuses:
        [GitLabIssueWorkItemStatus]? = nil,
    canUpdate: Bool = true
)
    -> GitLabIssueStatusSnapshot
{
    GitLabIssueStatusSnapshot(
        projectPath: "group/project",
        workItemID: "opaque-work-item-id",
        issueIID: 17,
        state: state,
        updatedAt: Date(
            timeIntervalSince1970:
                lockVersion == 8
                ? 1_785_240_000
                : 1_785_240_300
        ),
        lockVersion: lockVersion,
        currentStatus: currentStatus,
        allowedStatuses:
            allowedStatuses
            ?? [
                GitLabIssueWorkItemStatus(
                    id: "status-progress",
                    name: "In progress",
                    description: nil,
                    iconName: nil,
                    color: nil,
                    position: 1,
                    category: .inProgress
                ),
                makeDoneStatus(),
            ],
        canUpdate: canUpdate
    )
}

nonisolated func makeDoneStatus()
    -> GitLabIssueWorkItemStatus
{
    GitLabIssueWorkItemStatus(
        id: "status-done",
        name: "Done",
        description: nil,
        iconName: nil,
        color: nil,
        position: 2,
        category: .done
    )
}

nonisolated func makeStatusUpdateResult()
    -> GitLabIssueStatusUpdateResult
{
    GitLabIssueStatusUpdateResult(
        workItemID: "opaque-work-item-id",
        issueIID: 17,
        state: .closed,
        updatedAt: Date(
            timeIntervalSince1970: 1_785_240_300
        ),
        lockVersion: 9,
        status:
            GitLabIssueWorkItemStatus(
                id: "status-done",
                name: "Done",
                description: nil,
                iconName: nil,
                color: nil,
                position: 2,
                category: .done
            )
    )
}

private nonisolated func decodeStatusResponse(
    _ json: String
) throws -> GitLabIssueStatusGraphQLResponse {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
        GitLabIssueStatusGraphQLResponse.self,
        from: Data(json.utf8)
    )
}

private nonisolated func decodeUpdateResponse(
    _ json: String
) throws -> GitLabIssueStatusUpdateGraphQLResponse {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
        GitLabIssueStatusUpdateGraphQLResponse.self,
        from: Data(json.utf8)
    )
}

private nonisolated let supportedStatusResponseJSON =
    """
    {
      "data": {
        "project": {
          "fullPath": "group/project",
          "workItems": {
            "nodes": [
              {
                "id": "opaque-work-item-id",
                "iid": "17",
                "state": "OPEN",
                "updatedAt": "2026-07-28T12:00:00Z",
                "lockVersion": 8,
                "userPermissions": {"updateWorkItem": true},
                "workItemType": {
                  "name": "Issue",
                  "widgetDefinitions": [
                    {
                      "__typename": "WorkItemWidgetDefinitionStatus",
                      "allowedStatuses": [
                        {
                          "id": "status-progress",
                          "name": "In progress",
                          "position": 1,
                          "category": "IN_PROGRESS"
                        },
                        {
                          "id": "status-done",
                          "name": "Done",
                          "position": 2,
                          "category": "DONE"
                        }
                      ]
                    }
                  ]
                },
                "widgets": [
                  {
                    "__typename": "WorkItemWidgetStatus",
                    "status": {
                      "id": "status-progress",
                      "name": "In progress",
                      "position": 1,
                      "category": "IN_PROGRESS"
                    }
                  }
                ]
              }
            ],
            "pageInfo": {"hasNextPage": false}
          }
        }
      }
    }
    """

private nonisolated let successfulUpdateResponseJSON =
    """
    {
      "data": {
        "workItemUpdate": {
          "workItem": {
            "id": "opaque-work-item-id",
            "iid": "17",
            "state": "CLOSED",
            "updatedAt": "2026-07-28T12:05:00Z",
            "lockVersion": 9,
            "workItemType": {"name": "Issue"},
            "widgets": [
              {
                "__typename": "WorkItemWidgetStatus",
                "status": {
                  "id": "status-done",
                  "name": "Done",
                  "position": 2,
                  "category": "DONE"
                }
              }
            ]
          },
          "errors": []
        }
      }
    }
    """
