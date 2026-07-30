import Foundation

nonisolated enum GitLabIssueStatusCategory:
    String,
    CaseIterable,
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    case triage = "TRIAGE"
    case toDo = "TO_DO"
    case inProgress = "IN_PROGRESS"
    case done = "DONE"
    case canceled = "CANCELED"

    var issueState: GitLabIssueStateKind {
        switch self {
        case .triage, .toDo, .inProgress:
            .opened
        case .done, .canceled:
            .closed
        }
    }

    fileprivate var sortOrder: Int {
        switch self {
        case .triage:
            0
        case .toDo:
            1
        case .inProgress:
            2
        case .done:
            3
        case .canceled:
            4
        }
    }
}

nonisolated enum GitLabWorkItemState:
    String,
    Equatable,
    Sendable
{
    case open = "OPEN"
    case closed = "CLOSED"

    var issueState: GitLabIssueStateKind {
        switch self {
        case .open:
            .opened
        case .closed:
            .closed
        }
    }
}

nonisolated struct GitLabIssueWorkItemStatus:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    let id: String
    let name: String
    let description: String?
    let iconName: String?
    let color: String?
    let position: Int
    let category: GitLabIssueStatusCategory
}

nonisolated struct GitLabIssueStatusSnapshot:
    Equatable,
    Sendable
{
    let projectPath: String
    let workItemID: String
    let issueIID: Int
    let state: GitLabWorkItemState
    let updatedAt: Date
    let lockVersion: Int
    let currentStatus: GitLabIssueWorkItemStatus?
    let allowedStatuses: [GitLabIssueWorkItemStatus]
    let canUpdate: Bool
}

nonisolated struct GitLabIssueStatusUpdateResult:
    Equatable,
    Sendable
{
    let workItemID: String
    let issueIID: Int
    let state: GitLabWorkItemState
    let updatedAt: Date
    let lockVersion: Int
    let status: GitLabIssueWorkItemStatus
}

nonisolated struct GitLabGraphQLErrorPayload:
    Decodable,
    Equatable,
    Sendable
{
    let message: String
}

nonisolated struct GitLabIssueStatusGraphQLResponse:
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
        let state: String?
        let updatedAt: Date?
        let lockVersion: Int?
        let userPermissions: UserPermissions?
        let workItemType: WorkItemType?
        let widgets: [Widget?]?
    }

    struct UserPermissions: Decodable, Sendable {
        let updateWorkItem: Bool?
    }

    struct WorkItemType: Decodable, Sendable {
        let name: String?
        let widgetDefinitions: [WidgetDefinition?]?
    }

    struct Widget: Decodable, Sendable {
        let typeName: String?
        let status: Status?

        private enum CodingKeys: String, CodingKey {
            case typeName = "__typename"
            case status
        }
    }

    struct WidgetDefinition: Decodable, Sendable {
        let typeName: String?
        let allowedStatuses: [Status?]?

        private enum CodingKeys: String, CodingKey {
            case typeName = "__typename"
            case allowedStatuses
        }
    }

    struct Status: Decodable, Sendable {
        let id: String?
        let name: String?
        let description: String?
        let iconName: String?
        let color: String?
        let position: Int?
        let category: String?
    }

    func validatedSnapshot(
        projectPath expectedProjectPath: String,
        issueIID expectedIssueIID: Int
    ) -> GitLabIssueStatusSnapshot? {
        guard
            errors?.isEmpty != false,
            !expectedProjectPath.isEmpty,
            expectedProjectPath.trimmingCharacters(
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
            let workItemID = Self.opaqueID(
                workItem.id
            ),
            workItem.iid == String(expectedIssueIID),
            workItem.workItemType?.name == "Issue",
            let stateValue = workItem.state,
            let state = GitLabWorkItemState(
                rawValue: stateValue
            ),
            let updatedAt = workItem.updatedAt,
            let lockVersion = workItem.lockVersion,
            lockVersion >= 0,
            let canUpdate =
                workItem.userPermissions?
                    .updateWorkItem,
            let statusWidget = Self.onlyElement(
                workItem.widgets?
                    .compactMap { $0 }
                    .filter {
                        $0.typeName
                            == "WorkItemWidgetStatus"
                    }
            ),
            let statusDefinition = Self.onlyElement(
                workItem.workItemType?
                    .widgetDefinitions?
                    .compactMap { $0 }
                    .filter {
                        $0.typeName
                            == "WorkItemWidgetDefinitionStatus"
                    }
            ),
            let rawAllowed =
                statusDefinition.allowedStatuses,
            !rawAllowed.isEmpty
        else {
            return nil
        }

        let allowedStatuses =
            rawAllowed.compactMap {
                $0.flatMap(Self.validatedStatus)
            }
        guard
            allowedStatuses.count == rawAllowed.count,
            Set(allowedStatuses.map(\.id)).count
                == allowedStatuses.count
        else {
            return nil
        }

        let currentStatus: GitLabIssueWorkItemStatus?
        if let rawCurrent = statusWidget.status {
            guard
                let validatedCurrent =
                    Self.validatedStatus(
                        rawCurrent
                    ),
                let allowedCurrent =
                    allowedStatuses.first(
                        where: {
                            $0.id
                                == validatedCurrent.id
                        }
                    ),
                allowedCurrent == validatedCurrent,
                allowedCurrent.category.issueState
                    == state.issueState
            else {
                return nil
            }
            currentStatus = allowedCurrent
        } else {
            currentStatus = nil
        }

        return GitLabIssueStatusSnapshot(
            projectPath: expectedProjectPath,
            workItemID: workItemID,
            issueIID: expectedIssueIID,
            state: state,
            updatedAt: updatedAt,
            lockVersion: lockVersion,
            currentStatus: currentStatus,
            allowedStatuses:
                allowedStatuses.sorted(
                    by: Self.statusSort
                ),
            canUpdate: canUpdate
        )
    }
}

nonisolated struct GitLabIssueStatusUpdateGraphQLResponse:
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
            GitLabIssueStatusGraphQLResponse
                .WorkItem?
        let errors: [String]?
    }

    func validatedResult(
        workItemID expectedWorkItemID: String,
        issueIID expectedIssueIID: Int,
        selectedStatus: GitLabIssueWorkItemStatus,
        baselineLockVersion: Int
    ) -> GitLabIssueStatusUpdateResult? {
        guard
            errors?.isEmpty != false,
            GitLabIssueStatusGraphQLResponse
                .opaqueID(expectedWorkItemID)
                == expectedWorkItemID,
            expectedIssueIID > 0,
            let payload = data?.workItemUpdate,
            payload.errors?.isEmpty == true,
            let workItem = payload.workItem,
            GitLabIssueStatusGraphQLResponse
                .opaqueID(workItem.id)
                == expectedWorkItemID,
            workItem.iid == String(expectedIssueIID),
            workItem.workItemType?.name == "Issue",
            let stateValue = workItem.state,
            let state = GitLabWorkItemState(
                rawValue: stateValue
            ),
            let updatedAt = workItem.updatedAt,
            let lockVersion = workItem.lockVersion,
            lockVersion > baselineLockVersion,
            let statusWidget =
                GitLabIssueStatusGraphQLResponse
                    .onlyElement(
                        workItem.widgets?
                            .compactMap { $0 }
                            .filter {
                                $0.typeName
                                    == "WorkItemWidgetStatus"
                            }
                    ),
            let rawStatus = statusWidget.status,
            let status =
                GitLabIssueStatusGraphQLResponse
                    .validatedStatus(
                        rawStatus
                    ),
            status.id == selectedStatus.id,
            status.category
                == selectedStatus.category,
            status.category.issueState
                == state.issueState
        else {
            return nil
        }

        return GitLabIssueStatusUpdateResult(
            workItemID: expectedWorkItemID,
            issueIID: expectedIssueIID,
            state: state,
            updatedAt: updatedAt,
            lockVersion: lockVersion,
            status: status
        )
    }
}

nonisolated extension GitLabIssueStatusGraphQLResponse {
    static func opaqueID(
        _ value: String?
    ) -> String? {
        guard
            let value,
            !value.isEmpty,
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) == value
        else {
            return nil
        }
        return value
    }

    static func validatedStatus(
        _ raw: Status
    ) -> GitLabIssueWorkItemStatus? {
        guard
            let id = opaqueID(raw.id),
            let rawName = raw.name,
            let name =
                rawName.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .nilIfEmpty,
            let position = raw.position,
            position >= 0,
            let categoryValue = raw.category,
            let category =
                GitLabIssueStatusCategory(
                    rawValue: categoryValue
                )
        else {
            return nil
        }

        return GitLabIssueWorkItemStatus(
            id: id,
            name: name,
            description:
                raw.description?.trimmedNilIfEmpty,
            iconName:
                raw.iconName?.trimmedNilIfEmpty,
            color:
                raw.color?.trimmedNilIfEmpty,
            position: position,
            category: category
        )
    }

    static func onlyElement<Element>(
        _ elements: [Element]?
    ) -> Element? {
        guard
            let elements,
            elements.count == 1
        else {
            return nil
        }
        return elements[0]
    }

    static func statusSort(
        _ lhs: GitLabIssueWorkItemStatus,
        _ rhs: GitLabIssueWorkItemStatus
    ) -> Bool {
        if lhs.category != rhs.category {
            return lhs.category.sortOrder
                < rhs.category.sortOrder
        }
        if lhs.position != rhs.position {
            return lhs.position < rhs.position
        }
        let nameOrder =
            lhs.name.localizedCaseInsensitiveCompare(
                rhs.name
            )
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var trimmedNilIfEmpty: String? {
        trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        .nilIfEmpty
    }
}
