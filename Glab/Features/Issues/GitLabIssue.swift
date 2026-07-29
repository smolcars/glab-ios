import Foundation

nonisolated struct GitLabIssueRoute:
    Hashable,
    Sendable
{
    let projectID: Int
    let issueIID: Int
}

nonisolated enum GitLabIssueListMode:
    String,
    CaseIterable,
    Equatable,
    Hashable,
    Sendable
{
    case assigned
    case created

    var scope: String {
        switch self {
        case .assigned:
            "assigned_to_me"
        case .created:
            "created_by_me"
        }
    }

    var title: String {
        switch self {
        case .assigned:
            "Assigned"
        case .created:
            "Created"
        }
    }

    var emptyTitle: String {
        switch self {
        case .assigned:
            "No assigned issues"
        case .created:
            "No created issues"
        }
    }

    var emptyMessage: String {
        switch self {
        case .assigned:
            "Open issues assigned to you will appear here."
        case .created:
            "Open issues you created will appear here."
        }
    }
}

nonisolated enum GitLabIssueStateKind:
    Equatable,
    Sendable
{
    case opened
    case closed
    case unknown
}

nonisolated enum GitLabProjectIssueState:
    String,
    CaseIterable,
    Equatable,
    Hashable,
    Sendable
{
    case opened
    case closed

    var title: String {
        switch self {
        case .opened:
            "Open"
        case .closed:
            "Closed"
        }
    }

    func contains(
        _ issue: GitLabIssue
    ) -> Bool {
        switch (self, issue.stateKind) {
        case (.opened, .opened),
             (.closed, .closed):
            true
        default:
            false
        }
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
    let author: GitLabAPIUser
    let assignees: [GitLabAPIUser]
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
        GitLabWebURL.validated(webURL)
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
