import Foundation

nonisolated enum GitLabIssueFieldDatePresentation {
    static func range(
        start: String?,
        due: String?
    ) -> String? {
        switch (start, due) {
        case let (start?, due?):
            "\(start) – \(due)"
        case let (start?, nil):
            "Starts \(start)"
        case let (nil, due?):
            "Due \(due)"
        case (nil, nil):
            nil
        }
    }
}

nonisolated enum GitLabIssueGlobalID {
    static func user(_ id: Int) -> String {
        "gid://gitlab/User/\(id)"
    }

    static func milestone(_ id: Int) -> String {
        "gid://gitlab/Milestone/\(id)"
    }

    static func iteration(_ id: Int) -> String {
        "gid://gitlab/Iteration/\(id)"
    }

    static func numericID(
        _ value: String?,
        kind: String
    ) -> Int? {
        guard
            let value,
            let id = Int(
                value
                    .split(separator: "/")
                    .last
                    .map(String.init)
                    ?? ""
            ),
            id > 0,
            value
                == "gid://gitlab/\(kind)/\(id)"
        else {
            return nil
        }
        return id
    }
}

nonisolated struct GitLabIssueCreationStatusGraphQLResponse:
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
        let workItemTypes: WorkItemTypeConnection?
    }

    struct WorkItemTypeConnection:
        Decodable,
        Sendable
    {
        let nodes: [WorkItemType?]?
        let pageInfo:
            GitLabIssueStatusGraphQLResponse
                .PageInfo?
    }

    struct WorkItemType: Decodable, Sendable {
        let name: String?
        let widgetDefinitions:
            [
                GitLabIssueStatusGraphQLResponse
                    .WidgetDefinition?
            ]?
    }

    func validatedStatuses(
        projectPath expectedProjectPath: String
    ) -> [GitLabIssueWorkItemStatus]? {
        guard
            errors?.isEmpty != false,
            let project = data?.project,
            project.fullPath
                == expectedProjectPath,
            let connection =
                project.workItemTypes,
            connection.pageInfo?
                .hasNextPage == false,
            let nodes =
                connection.nodes?
                .compactMap({ $0 }),
            nodes.count == 1,
            let issueType = nodes.first,
            issueType.name == "Issue",
            let statusDefinition =
                GitLabIssueStatusGraphQLResponse
                .onlyElement(
                    issueType
                        .widgetDefinitions?
                        .compactMap { $0 }
                        .filter {
                            $0.typeName
                                == "WorkItemWidgetDefinitionStatus"
                        }
                ),
            let rawStatuses =
                statusDefinition
                .allowedStatuses,
            !rawStatuses.isEmpty
        else {
            return nil
        }

        let statuses =
            rawStatuses.compactMap {
                $0.flatMap(
                    GitLabIssueStatusGraphQLResponse
                        .validatedStatus
                )
            }
        guard
            statuses.count
                == rawStatuses.count,
            Set(statuses.map(\.id)).count
                == statuses.count
        else {
            return nil
        }
        return statuses.sorted(
            by:
                GitLabIssueStatusGraphQLResponse
                .statusSort
        )
    }
}

nonisolated struct GitLabIssueCreateGraphQLResponse:
    Decodable,
    Sendable
{
    let data: DataPayload?
    let errors: [GitLabGraphQLErrorPayload]?

    struct DataPayload: Decodable, Sendable {
        let createIssue: Payload?
    }

    struct Payload: Decodable, Sendable {
        let issue: Issue?
        let errors: [String]?
    }

    struct Issue: Decodable, Sendable {
        let iid: String?
        let projectID: Int?

        private enum CodingKeys:
            String,
            CodingKey
        {
            case iid
            case projectID = "projectId"
        }
    }

    func validatedRoute(
        projectID expectedProjectID: Int
    ) -> GitLabIssueRoute? {
        guard
            errors?.isEmpty != false,
            let payload = data?.createIssue,
            payload.errors?.isEmpty == true,
            let issue = payload.issue,
            issue.projectID == expectedProjectID,
            let iidValue = issue.iid,
            let iid = Int(iidValue),
            iid > 0
        else {
            return nil
        }
        return GitLabIssueRoute(
            projectID: expectedProjectID,
            issueIID: iid
        )
    }
}

nonisolated struct GitLabIssueGraphQLBody<
    Variables
>: Encodable, Sendable
where Variables: Encodable & Sendable {
    let query: String
    let variables: Variables
}
