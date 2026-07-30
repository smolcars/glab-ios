import Foundation

nonisolated struct GitLabIssuePlanningSnapshot:
    Equatable,
    Sendable
{
    let projectPath: String
    let workItemID: String
    let issueIID: Int
    let milestoneID: Int?
    let iterationID: Int?
    let canUpdate: Bool
}

nonisolated enum GitLabIssuePlanningChange:
    Equatable,
    Sendable
{
    case milestone(Int?)
    case iteration(Int?)
}

nonisolated enum GitLabIssuePlanningAvailability:
    Equatable,
    Sendable
{
    case supported(
        GitLabIssuePlanningSnapshot
    )
    case unavailable
}

nonisolated enum GitLabIssuePlanningMutationOutcome:
    Equatable,
    Sendable
{
    case updated(
        GitLabIssuePlanningSnapshot
    )
    case rejected
    case deliveryUnknown
}

nonisolated struct GitLabIssuePlanningGraphQLResponse:
    Decodable,
    Sendable
{
    let data: DataPayload?
    let errors: [GitLabGraphQLErrorPayload]?

    struct DataPayload: Decodable, Sendable {
        let project: Project?
    }

    struct Project: Decodable, Sendable {
        let fullPath: String?
        let workItems: WorkItemConnection?
    }

    struct WorkItemConnection: Decodable, Sendable {
        let nodes: [WorkItem?]?
        let pageInfo: PageInfo?
    }

    struct PageInfo: Decodable, Sendable {
        let hasNextPage: Bool?
    }

    struct WorkItem: Decodable, Sendable {
        let id: String?
        let iid: String?
        let userPermissions: UserPermissions?
        let workItemType: WorkItemType?
        let widgets: [Widget?]?
    }

    struct UserPermissions: Decodable, Sendable {
        let updateWorkItem: Bool?
    }

    struct WorkItemType: Decodable, Sendable {
        let name: String?
    }

    struct Widget: Decodable, Sendable {
        let typeName: String?
        let milestone: GlobalID?
        let iteration: GlobalID?

        private enum CodingKeys: String, CodingKey {
            case typeName = "__typename"
            case milestone
            case iteration
        }
    }

    struct GlobalID: Decodable, Sendable {
        let id: String?
    }

    func validatedSnapshot(
        projectPath expectedProjectPath: String,
        issueIID expectedIssueIID: Int
    ) -> GitLabIssuePlanningSnapshot? {
        guard
            errors?.isEmpty != false,
            !expectedProjectPath.isEmpty,
            expectedProjectPath
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) == expectedProjectPath,
            expectedIssueIID > 0,
            let project = data?.project,
            project.fullPath == expectedProjectPath,
            let connection = project.workItems,
            connection.pageInfo?.hasNextPage == false,
            let nodes = connection.nodes,
            nodes.count == 1,
            let workItem = nodes[0],
            let workItemID =
                GitLabIssueStatusGraphQLResponse
                    .opaqueID(workItem.id),
            workItem.iid
                == String(expectedIssueIID),
            workItem.workItemType?.name == "Issue",
            let canUpdate =
                workItem.userPermissions?
                    .updateWorkItem,
            let fields =
                Self.validatedFields(
                    workItem.widgets
                )
        else {
            return nil
        }

        return GitLabIssuePlanningSnapshot(
            projectPath: expectedProjectPath,
            workItemID: workItemID,
            issueIID: expectedIssueIID,
            milestoneID:
                fields.milestoneID,
            iterationID:
                fields.iterationID,
            canUpdate: canUpdate
        )
    }

    static func validatedFields(
        _ widgets: [Widget?]?
    ) -> (
        milestoneID: Int?,
        iterationID: Int?
    )? {
        let widgets =
            widgets?.compactMap { $0 }
            ?? []
        let milestoneWidgets =
            widgets.filter {
                $0.typeName
                    == "WorkItemWidgetMilestone"
            }
        let iterationWidgets =
            widgets.filter {
                $0.typeName
                    == "WorkItemWidgetIteration"
            }
        guard
            milestoneWidgets.count <= 1,
            iterationWidgets.count <= 1
        else {
            return nil
        }

        let milestoneID: Int?
        if
            let rawID =
                milestoneWidgets
                    .first?
                    .milestone?
                    .id
        {
            guard
                let parsed =
                    GitLabIssueGlobalID
                        .numericID(
                            rawID,
                            kind: "Milestone"
                        )
            else {
                return nil
            }
            milestoneID = parsed
        } else {
            milestoneID = nil
        }

        let iterationID: Int?
        if
            let rawID =
                iterationWidgets
                    .first?
                    .iteration?
                    .id
        {
            guard
                let parsed =
                    GitLabIssueGlobalID
                        .numericID(
                            rawID,
                            kind: "Iteration"
                        )
            else {
                return nil
            }
            iterationID = parsed
        } else {
            iterationID = nil
        }

        return (
            milestoneID,
            iterationID
        )
    }
}

nonisolated struct GitLabIssuePlanningUpdateGraphQLResponse:
    Decodable,
    Sendable
{
    let data: DataPayload?
    let errors: [GitLabGraphQLErrorPayload]?

    struct DataPayload: Decodable, Sendable {
        let workItemUpdate: Payload?
    }

    struct Payload: Decodable, Sendable {
        let workItem:
            GitLabIssuePlanningGraphQLResponse
                .WorkItem?
        let errors: [String]?
    }

    func validatedSnapshot(
        baseline:
            GitLabIssuePlanningSnapshot,
        change:
            GitLabIssuePlanningChange
    ) -> GitLabIssuePlanningSnapshot? {
        guard
            errors?.isEmpty != false,
            let payload = data?.workItemUpdate,
            payload.errors?.isEmpty == true,
            let workItem = payload.workItem,
            GitLabIssueStatusGraphQLResponse
                .opaqueID(workItem.id)
                == baseline.workItemID,
            workItem.iid
                == String(baseline.issueIID),
            workItem.workItemType?.name == "Issue",
            let fields =
                GitLabIssuePlanningGraphQLResponse
                    .validatedFields(
                        workItem.widgets
                    )
        else {
            return nil
        }

        let expected =
            baseline.applying(change)
        guard
            fields.milestoneID
                == expected.milestoneID,
            fields.iterationID
                == expected.iterationID
        else {
            return nil
        }
        return expected
    }
}

nonisolated extension GitLabIssuePlanningSnapshot {
    func applying(
        _ change:
            GitLabIssuePlanningChange
    ) -> Self {
        switch change {
        case let .milestone(id):
            Self(
                projectPath: projectPath,
                workItemID: workItemID,
                issueIID: issueIID,
                milestoneID: id,
                iterationID: iterationID,
                canUpdate: canUpdate
            )
        case let .iteration(id):
            Self(
                projectPath: projectPath,
                workItemID: workItemID,
                issueIID: issueIID,
                milestoneID: milestoneID,
                iterationID: id,
                canUpdate: canUpdate
            )
        }
    }
}
