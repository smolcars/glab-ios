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

    static let assignedMergeRequests:
        GitLabAPIRequest<[GitLabHomeMergeRequest]> = .get(
            requires: .read,
            path: ["merge_requests"],
            query: workQuery(scope: "assigned_to_me")
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
            query: projectQuery(filter: .init(name: "membership", value: "true"))
        )

    static let starredProjects:
        GitLabAPIRequest<[GitLabHomeProject]> = .get(
            requires: .read,
            path: ["projects"],
            query: projectQuery(filter: .init(name: "starred", value: "true"))
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
        filter: URLQueryItem
    ) -> [URLQueryItem] {
        [
            filter,
            .init(name: "order_by", value: "last_activity_at"),
            .init(name: "sort", value: "desc"),
            .init(name: "simple", value: "true"),
            .init(name: "per_page", value: "3"),
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

    var workItem: GitLabHomeWorkItem {
        GitLabHomeWorkItem(
            id: "issue:\(projectID):\(iid)",
            title: title,
            detail: references?.full ?? "#\(iid)",
            webURL: webURL
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectID = "project_id"
        case title
        case webURL = "web_url"
        case references
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

    var workItem: GitLabHomeWorkItem {
        GitLabHomeWorkItem(
            id: "merge-request:\(projectID):\(iid)",
            title: title,
            detail: references?.full ?? "!\(iid)",
            webURL: webURL
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectID = "project_id"
        case title
        case webURL = "web_url"
        case references
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
