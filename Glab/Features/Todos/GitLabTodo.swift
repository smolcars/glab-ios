import Foundation

nonisolated enum GitLabTodoState:
    String,
    CaseIterable,
    Decodable,
    Equatable,
    Hashable,
    Sendable
{
    case pending
    case done

    var title: String {
        rawValue.capitalized
    }
}

nonisolated enum GitLabTodoTargetFilter:
    String,
    CaseIterable,
    Equatable,
    Hashable,
    Sendable
{
    case all
    case issues
    case mergeRequests

    var title: String {
        switch self {
        case .all:
            "All"
        case .issues:
            "Issues"
        case .mergeRequests:
            "Merge Requests"
        }
    }

    var queryValue: String? {
        switch self {
        case .all:
            nil
        case .issues:
            "Issue"
        case .mergeRequests:
            "MergeRequest"
        }
    }
}

nonisolated enum GitLabTodoTargetType:
    Decodable,
    Equatable,
    Sendable
{
    case issue
    case mergeRequest
    case commit
    case epic
    case design
    case alert
    case project
    case namespace
    case vulnerability
    case wikiPage
    case unknown(String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self = switch value {
        case "Issue":
            .issue
        case "MergeRequest":
            .mergeRequest
        case "Commit":
            .commit
        case "Epic":
            .epic
        case "DesignManagement::Design":
            .design
        case "AlertManagement::Alert":
            .alert
        case "Project":
            .project
        case "Namespace":
            .namespace
        case "Vulnerability":
            .vulnerability
        case "WikiPage::Meta":
            .wikiPage
        default:
            .unknown(value)
        }
    }

    var title: String {
        switch self {
        case .issue:
            "Issue"
        case .mergeRequest:
            "Merge request"
        case .commit:
            "Commit"
        case .epic:
            "Epic"
        case .design:
            "Design"
        case .alert:
            "Alert"
        case .project:
            "Project"
        case .namespace:
            "Namespace"
        case .vulnerability:
            "Vulnerability"
        case .wikiPage:
            "Wiki page"
        case let .unknown(value):
            value.isEmpty ? "Unknown" : value
        }
    }

    var systemImage: String {
        switch self {
        case .issue:
            "smallcircle.filled.circle"
        case .mergeRequest:
            "arrow.triangle.branch"
        case .commit:
            "point.topleft.down.to.point.bottomright.curvepath"
        case .epic:
            "bolt.fill"
        case .design:
            "paintbrush"
        case .alert:
            "exclamationmark.triangle"
        case .project:
            "folder"
        case .namespace:
            "person.2"
        case .vulnerability:
            "exclamationmark.shield"
        case .wikiPage:
            "doc.text"
        case .unknown:
            "questionmark.circle"
        }
    }

    var gitLabIcon: GitLabIcon? {
        switch self {
        case .issue:
            .workItemIssue
        case .mergeRequest:
            .mergeRequest
        case .commit:
            .commit
        case .epic:
            .epic
        case .alert:
            .alertManagement
        case .project:
            .project
        case .namespace:
            .group
        case .design,
             .vulnerability,
             .wikiPage,
             .unknown:
            nil
        }
    }
}

nonisolated enum GitLabTodoAction:
    Decodable,
    Equatable,
    Sendable
{
    case assigned
    case mentioned
    case buildFailed
    case marked
    case approvalRequired
    case unmergeable
    case directlyAddressed
    case mergeTrainRemoved
    case memberAccessRequested
    case unknown(String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self = switch value {
        case "assigned":
            .assigned
        case "mentioned":
            .mentioned
        case "build_failed":
            .buildFailed
        case "marked":
            .marked
        case "approval_required":
            .approvalRequired
        case "unmergeable":
            .unmergeable
        case "directly_addressed":
            .directlyAddressed
        case "merge_train_removed":
            .mergeTrainRemoved
        case "member_access_requested":
            .memberAccessRequested
        default:
            .unknown(value)
        }
    }

    var title: String {
        switch self {
        case .assigned:
            "Assigned"
        case .mentioned:
            "Mentioned"
        case .buildFailed:
            "Build failed"
        case .marked:
            "Marked"
        case .approvalRequired:
            "Approval required"
        case .unmergeable:
            "Unmergeable"
        case .directlyAddressed:
            "Directly addressed"
        case .mergeTrainRemoved:
            "Removed from merge train"
        case .memberAccessRequested:
            "Member access requested"
        case let .unknown(value):
            Self.unknownTitle(value)
        }
    }

    private static func unknownTitle(
        _ value: String
    ) -> String {
        let words = value
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
        return words.isEmpty ? "Unknown action" : words
    }
}

nonisolated enum GitLabTodoNativeRoute:
    Hashable,
    Sendable
{
    case issue(GitLabIssueRoute)
    case mergeRequest(GitLabMergeRequestRoute)
}

nonisolated struct GitLabTodoProject:
    Decodable,
    Equatable,
    Sendable
{
    let id: Int?
    let name: String?
    let nameWithNamespace: String?
    let path: String?
    let pathWithNamespace: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameWithNamespace = "name_with_namespace"
        case path
        case pathWithNamespace = "path_with_namespace"
    }
}

nonisolated struct GitLabTodoTarget:
    Decodable,
    Equatable,
    Sendable
{
    let id: Int?
    let iid: Int?
    let projectID: Int?
    let title: String?
    let name: String?
    let description: String?
    let state: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectID = "project_id"
        case title
        case name
        case description
        case state
    }
}

nonisolated struct GitLabTodo:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let project: GitLabTodoProject?
    let author: GitLabAPIUser?
    let action: GitLabTodoAction
    let targetType: GitLabTodoTargetType
    let target: GitLabTodoTarget?
    let targetURL: URL?
    let body: String?
    let state: GitLabTodoState
    let createdAt: Date
    let updatedAt: Date

    var title: String {
        target?.title?.todoTrimmedNonempty
            ?? target?.name?.todoTrimmedNonempty
            ?? body?.todoTrimmedNonempty
            ?? "Untitled Todo"
    }

    var displayBody: String? {
        guard
            let value = body?.todoTrimmedNonempty,
            value != title
        else {
            return nil
        }
        return value
    }

    var catchUpBody: String? {
        if let body = distinctCatchUpSource(body) {
            return body
        }
        return distinctCatchUpSource(
            target?.description
        )
    }

    var projectTitle: String {
        project?.nameWithNamespace?.todoTrimmedNonempty
            ?? project?.name?.todoTrimmedNonempty
            ?? project?.pathWithNamespace?.todoTrimmedNonempty
            ?? project?.path?.todoTrimmedNonempty
            ?? "No project"
    }

    var authorTitle: String {
        author?.displayName ?? "Unknown author"
    }

    var safeTargetURL: URL? {
        GitLabWebURL.validated(targetURL)
    }

    var nativeRoute: GitLabTodoNativeRoute? {
        guard
            let iid = target?.iid,
            let projectID =
                target?.projectID ?? project?.id
        else {
            return nil
        }

        return switch targetType {
        case .issue:
            .issue(
                GitLabIssueRoute(
                    projectID: projectID,
                    issueIID: iid
                )
            )
        case .mergeRequest:
            .mergeRequest(
                GitLabMergeRequestRoute(
                    projectID: projectID,
                    mergeRequestIID: iid
                )
            )
        case
            .commit,
            .epic,
            .design,
            .alert,
            .project,
            .namespace,
            .vulnerability,
            .wikiPage,
            .unknown:
            nil
        }
    }

    private func distinctCatchUpSource(
        _ source: String?
    ) -> String? {
        guard
            let source,
            let normalized =
                source.todoTrimmedNonempty,
            normalized != title
        else {
            return nil
        }
        return source
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case project
        case author
        case action = "action_name"
        case targetType = "target_type"
        case target
        case targetURL = "target_url"
        case body
        case state
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated extension GitLabTodo {
    func replacingEditedTarget(
        with result: GitLabResourceEditResult
    ) -> GitLabTodo? {
        let replacement: GitLabTodoTarget

        switch result {
        case let .issue(issue):
            guard
                targetType == .issue,
                nativeRoute == .issue(issue.route),
                target?.id == nil
                    || target?.id == issue.id
            else {
                return nil
            }
            replacement = GitLabTodoTarget(
                id: issue.id,
                iid: issue.iid,
                projectID: issue.projectID,
                title: issue.title,
                name: target?.name,
                description: issue.description,
                state: issue.state
            )
        case let .mergeRequest(mergeRequest):
            guard
                targetType == .mergeRequest,
                nativeRoute
                    == .mergeRequest(
                        mergeRequest.route
                    ),
                target?.id == nil
                    || target?.id
                        == mergeRequest.id
            else {
                return nil
            }
            replacement = GitLabTodoTarget(
                id: mergeRequest.id,
                iid: mergeRequest.iid,
                projectID:
                    mergeRequest.projectID,
                title: mergeRequest.title,
                name: target?.name,
                description:
                    mergeRequest.description,
                state: mergeRequest.state
            )
        }

        return GitLabTodo(
            id: id,
            project: project,
            author: author,
            action: action,
            targetType: targetType,
            target: replacement,
            targetURL: targetURL,
            body: body,
            state: state,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private nonisolated extension String {
    var todoTrimmedNonempty: String? {
        let value = trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return value.isEmpty ? nil : value
    }
}
