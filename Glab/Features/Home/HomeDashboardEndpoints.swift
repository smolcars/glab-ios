import Foundation

nonisolated enum HomeDashboardEndpoints {
    static let currentUser:
        GitLabAPIRequest<GitLabAuthenticatedUser> = .get(
            requires: .read,
            path: ["user"]
        )

    static let assignedIssues:
        GitLabAPIRequest<[GitLabHomeIssue]> = .get(
            requires: .read,
            path: ["issues"],
            query: workQuery(scope: "assigned_to_me")
        )

    static let createdIssues:
        GitLabAPIRequest<[GitLabHomeIssue]> = .get(
            requires: .read,
            path: ["issues"],
            query: workQuery(scope: "created_by_me")
        )

    static let assignedMergeRequests:
        GitLabAPIRequest<[GitLabHomeMergeRequest]> = .get(
            requires: .read,
            path: ["merge_requests"],
            query: workQuery(scope: "assigned_to_me")
        )

    static let createdMergeRequests:
        GitLabAPIRequest<[GitLabHomeMergeRequest]> = .get(
            requires: .read,
            path: ["merge_requests"],
            query: workQuery(scope: "created_by_me")
        )

    static let reviewRequests:
        GitLabAPIRequest<[GitLabHomeMergeRequest]> = .get(
            requires: .read,
            path: ["merge_requests"],
            query: workQuery(scope: "reviews_for_me")
        )

    static let recentProjects:
        GitLabAPIRequest<[GitLabHomeProject]> = .get(
            requires: .read,
            path: ["projects"],
            query: projectQuery(
                filter: .init(name: "membership", value: "true"),
                perPage: GitLabProjectEndpoints
                    .membershipActivityPageSize
            )
        )

    static let starredProjects:
        GitLabAPIRequest<[GitLabHomeProject]> = .get(
            requires: .read,
            path: ["projects"],
            query: projectQuery(
                filter: .init(name: "starred", value: "true"),
                perPage: 3
            )
        )

    private static func workQuery(
        scope: String
    ) -> [URLQueryItem] {
        [
            .init(name: "scope", value: scope),
            .init(name: "state", value: "opened"),
            .init(name: "order_by", value: "updated_at"),
            .init(name: "sort", value: "desc"),
            .init(name: "per_page", value: "3"),
        ]
    }

    private static func projectQuery(
        filter: URLQueryItem,
        perPage: Int
    ) -> [URLQueryItem] {
        [
            filter,
            .init(name: "order_by", value: "last_activity_at"),
            .init(name: "sort", value: "desc"),
            .init(name: "simple", value: "true"),
            .init(name: "per_page", value: String(perPage)),
        ]
    }
}

nonisolated struct GitLabHomeIssue:
    Decodable,
    Equatable,
    Sendable
{
    let id: Int
    let iid: Int
    let projectID: Int
    let title: String
    let webURL: URL?
    let references: GitLabHomeReference?
    let updatedAt: Date?

    var workItem: GitLabHomeWorkItem {
        GitLabHomeWorkItem(
            id: "issue:\(projectID):\(iid)",
            title: title,
            detail: references?.full ?? "#\(iid)",
            webURL: webURL,
            updatedAt: updatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectID = "project_id"
        case title
        case webURL = "web_url"
        case references
        case updatedAt = "updated_at"
    }
}

nonisolated struct GitLabHomeMergeRequest:
    Decodable,
    Equatable,
    Sendable
{
    let id: Int
    let iid: Int
    let projectID: Int
    let title: String
    let webURL: URL?
    let references: GitLabHomeReference?
    let updatedAt: Date?

    var workItem: GitLabHomeWorkItem {
        GitLabHomeWorkItem(
            id: "merge-request:\(projectID):\(iid)",
            title: title,
            detail: references?.full ?? "!\(iid)",
            webURL: webURL,
            updatedAt: updatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectID = "project_id"
        case title
        case webURL = "web_url"
        case references
        case updatedAt = "updated_at"
    }
}

nonisolated struct GitLabHomeProject:
    Decodable,
    Equatable,
    Sendable
{
    let id: Int
    let name: String
    let nameWithNamespace: String?
    let pathWithNamespace: String
    let webURL: URL?

    var workItem: GitLabHomeWorkItem {
        GitLabHomeWorkItem(
            id: "project:\(id)",
            title: nameWithNamespace ?? name,
            detail: pathWithNamespace,
            webURL: webURL
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameWithNamespace = "name_with_namespace"
        case pathWithNamespace = "path_with_namespace"
        case webURL = "web_url"
    }
}

nonisolated struct GitLabHomeReference:
    Decodable,
    Equatable,
    Sendable
{
    let full: String
}
