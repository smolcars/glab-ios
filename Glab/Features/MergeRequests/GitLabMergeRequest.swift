import Foundation

nonisolated struct GitLabMergeRequestRoute:
    Hashable,
    Sendable
{
    let projectID: Int
    let mergeRequestIID: Int
}

nonisolated enum GitLabMergeRequestListMode:
    String,
    Equatable,
    Hashable,
    Sendable
{
    case assigned
    case reviewRequested

    var scope: String {
        switch self {
        case .assigned:
            "assigned_to_me"
        case .reviewRequested:
            "reviews_for_me"
        }
    }

    var title: String {
        switch self {
        case .assigned:
            "Assigned Merge Requests"
        case .reviewRequested:
            "Review Requests"
        }
    }

    var emptyMessage: String {
        switch self {
        case .assigned:
            "Open merge requests assigned to you will appear here."
        case .reviewRequested:
            "Open merge requests awaiting your review will appear here."
        }
    }

    var emptyTitle: String {
        switch self {
        case .assigned:
            "No assigned merge requests"
        case .reviewRequested:
            "No review requests"
        }
    }
}

nonisolated enum GitLabMergeRequestStateKind:
    Equatable,
    Sendable
{
    case opened
    case closed
    case merged
    case locked
    case unknown
}

nonisolated struct GitLabMergeRequestReferences:
    Decodable,
    Equatable,
    Sendable
{
    let short: String
    let relative: String
    let full: String
}

nonisolated struct GitLabMergeRequest:
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
    let draft: Bool?
    let legacyWorkInProgress: Bool?
    let labels: [String]
    let author: GitLabAPIUser
    let assignees: [GitLabAPIUser]
    let reviewers: [GitLabAPIUser]
    let sourceBranch: String
    let targetBranch: String
    let userNotesCount: Int
    let createdAt: Date
    let updatedAt: Date
    let closedAt: Date?
    let mergedAt: Date?
    let webURL: URL?
    let references: GitLabMergeRequestReferences

    var route: GitLabMergeRequestRoute {
        GitLabMergeRequestRoute(
            projectID: projectID,
            mergeRequestIID: iid
        )
    }

    var isDraft: Bool {
        draft ?? legacyWorkInProgress ?? false
    }

    var stateKind: GitLabMergeRequestStateKind {
        switch normalizedState {
        case "opened":
            .opened
        case "closed":
            .closed
        case "merged":
            .merged
        case "locked":
            .locked
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
        case draft
        case legacyWorkInProgress = "work_in_progress"
        case labels
        case author
        case assignees
        case reviewers
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
        case userNotesCount = "user_notes_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
        case mergedAt = "merged_at"
        case webURL = "web_url"
        case references
    }
}

nonisolated struct GitLabMergeRequestPage:
    Equatable,
    Sendable
{
    let mergeRequests: [GitLabMergeRequest]
    let nextPageURL: URL?
}
