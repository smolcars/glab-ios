import Foundation

nonisolated struct GitLabIssueRoute:
    Hashable,
    Sendable
{
    let projectID: Int
    let issueIID: Int
}

nonisolated enum GitLabIssueStateKind:
    Equatable,
    Sendable
{
    case opened
    case closed
    case unknown
}

nonisolated struct GitLabIssueUser:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let username: String
    let name: String
    let avatarURL: URL?
    let webURL: URL?

    var summary: GitLabUserSummary {
        GitLabUserSummary(
            id: id,
            username: username,
            name: name,
            avatarURL: avatarURL
        )
    }

    var displayName: String {
        summary.displayName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case name
        case avatarURL = "avatar_url"
        case webURL = "web_url"
    }
}

nonisolated struct GitLabIssueMilestone:
    Decodable,
    Equatable,
    Sendable
{
    let id: Int
    let iid: Int
    let title: String
    let state: String
    let dueDate: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case iid
        case title
        case state
        case dueDate = "due_date"
    }
}

nonisolated struct GitLabIssueReferences:
    Decodable,
    Equatable,
    Sendable
{
    let short: String
    let relative: String
    let full: String
}

nonisolated struct GitLabIssue:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let iid: Int
    let projectID: Int
    let title: String
    let description: String?
    let state: String
    let confidential: Bool
    let labels: [String]
    let author: GitLabIssueUser
    let assignees: [GitLabIssueUser]
    let milestone: GitLabIssueMilestone?
    let dueDate: String?
    let userNotesCount: Int
    let createdAt: Date
    let updatedAt: Date
    let closedAt: Date?
    let webURL: URL?
    let references: GitLabIssueReferences

    var route: GitLabIssueRoute {
        GitLabIssueRoute(
            projectID: projectID,
            issueIID: iid
        )
    }

    var stateKind: GitLabIssueStateKind {
        switch normalizedState {
        case "opened":
            .opened
        case "closed":
            .closed
        default:
            .unknown
        }
    }

    var stateTitle: String {
        normalizedState.isEmpty
            ? "Unknown"
            : normalizedState.capitalized
    }

    var safeWebURL: URL? {
        guard
            let webURL,
            let components = URLComponents(
                url: webURL,
                resolvingAgainstBaseURL: false
            ),
            components.scheme?.lowercased() == "https",
            components.host != nil,
            components.user == nil,
            components.password == nil
        else {
            return nil
        }

        return webURL
    }

    private var normalizedState: String {
        state.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        .lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectID = "project_id"
        case title
        case description
        case state
        case confidential
        case labels
        case author
        case assignees
        case milestone
        case dueDate = "due_date"
        case userNotesCount = "user_notes_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
        case webURL = "web_url"
        case references
    }
}

nonisolated struct GitLabIssuePage:
    Equatable,
    Sendable
{
    let issues: [GitLabIssue]
    let nextPageURL: URL?
}
