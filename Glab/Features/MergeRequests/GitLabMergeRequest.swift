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

nonisolated struct GitLabMergeRequestDiffRefs:
    Decodable,
    Equatable,
    Sendable
{
    let baseSHA: String
    let startSHA: String
    let headSHA: String

    var identity:
        GitLabMergeRequestDiffVersionIdentity?
    {
        GitLabMergeRequestDiffVersionIdentity(
            baseSHA: baseSHA,
            startSHA: startSHA,
            headSHA: headSHA
        )
    }

    private enum CodingKeys: String, CodingKey {
        case baseSHA = "base_sha"
        case startSHA = "start_sha"
        case headSHA = "head_sha"
    }
}

nonisolated struct GitLabMergeRequestDiffVersion:
    Decodable,
    Equatable,
    Sendable
{
    let id: Int
    let baseCommitSHA: String
    let startCommitSHA: String
    let headCommitSHA: String
    let state: String?

    var identity:
        GitLabMergeRequestDiffVersionIdentity?
    {
        GitLabMergeRequestDiffVersionIdentity(
            baseSHA: baseCommitSHA,
            startSHA: startCommitSHA,
            headSHA: headCommitSHA
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case baseCommitSHA = "base_commit_sha"
        case startCommitSHA = "start_commit_sha"
        case headCommitSHA = "head_commit_sha"
        case state
    }
}

nonisolated struct GitLabMergeRequestHeadPipeline:
    Decodable,
    Equatable,
    Sendable
{
    let id: Int
    let status: String
    let webURL: URL?

    var safeWebURL: URL? {
        GitLabWebURL.validated(webURL)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case webURL = "web_url"
    }
}

nonisolated struct
    GitLabMergeRequestUserPermissions:
    Decodable,
    Equatable,
    Sendable
{
    let canMerge: Bool?

    init(canMerge: Bool?) {
        self.canMerge = canMerge
    }

    private enum CodingKeys: String, CodingKey {
        case canMerge = "can_merge"
    }
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
    let sha: String?
    let diffRefs: GitLabMergeRequestDiffRefs?
    let changesCount: String?
    let detailedMergeStatus: String?
    let hasConflicts: Bool?
    let blockingDiscussionsResolved: Bool?
    let headPipeline:
        GitLabMergeRequestHeadPipeline?
    let mergeWhenPipelineSucceeds: Bool?
    let userPermissions:
        GitLabMergeRequestUserPermissions?

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

    var safeChangesURL: URL? {
        safeWebURL?
            .appendingPathComponent("diffs")
    }

    var diffHeadSHA: String? {
        Self.nonemptyTrimmed(diffRefs?.headSHA)
            ?? Self.nonemptyTrimmed(sha)
    }

    private var normalizedState: String {
        state.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        .lowercased()
    }

    private static func nonemptyTrimmed(
        _ value: String?
    ) -> String? {
        let normalized = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalized?.isEmpty == false
            ? normalized
            : nil
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
        case sha
        case diffRefs = "diff_refs"
        case changesCount = "changes_count"
        case detailedMergeStatus =
            "detailed_merge_status"
        case hasConflicts = "has_conflicts"
        case blockingDiscussionsResolved =
            "blocking_discussions_resolved"
        case headPipeline = "head_pipeline"
        case mergeWhenPipelineSucceeds =
            "merge_when_pipeline_succeeds"
        case userPermissions = "user"
    }
}

nonisolated struct GitLabMergeRequestPage:
    Equatable,
    Sendable
{
    let mergeRequests: [GitLabMergeRequest]
    let nextPageURL: URL?
}
