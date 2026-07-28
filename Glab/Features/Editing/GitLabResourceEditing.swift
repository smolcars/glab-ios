import Foundation

nonisolated enum GitLabResourceEditResult:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case issue(GitLabIssue)
    case mergeRequest(GitLabMergeRequest)

    var snapshot: GitLabResourceEditSnapshot {
        switch self {
        case let .issue(issue):
            GitLabResourceEditSnapshot(
                issue: issue
            )
        case let .mergeRequest(mergeRequest):
            GitLabResourceEditSnapshot(
                mergeRequest: mergeRequest
            )
        }
    }

    var description: String {
        "GitLabResourceEditResult(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated protocol GitLabResourceEditing:
    Sendable
{
    func loadLatest(
        _ target: GitLabResourceEditTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult

    func update(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceEditChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
}
