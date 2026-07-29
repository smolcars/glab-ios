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

    func invalidateAffectedReads(
        for target: GitLabResourceEditTarget
    ) async

    func invalidateProjectLabels(
        projectID: Int
    ) async

    func loadLabelsPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectLabel
        >

    func loadMembersPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectMember
        >

    func updateMetadata(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceMetadataChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
}

extension GitLabResourceEditing {
    func invalidateProjectLabels(
        projectID: Int
    ) async {}

    func loadLabelsPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectLabel
        >
    {
        throw .api(.invalidResponse)
    }

    func loadMembersPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectMember
        >
    {
        throw .api(.invalidResponse)
    }

    func updateMetadata(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceMetadataChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        throw .api(.invalidResponse)
    }
}
