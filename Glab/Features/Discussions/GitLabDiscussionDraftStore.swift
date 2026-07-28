import Foundation

nonisolated struct GitLabDiscussionDraftKey:
    Codable,
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    private enum ResourceKind:
        String,
        Codable,
        Sendable
    {
        case issue
        case mergeRequest
    }

    let accountID: GitLabAccountID
    let discussionID: String?

    private let resourceKind: ResourceKind
    private let projectID: Int
    private let resourceIID: Int

    init(
        accountID: GitLabAccountID,
        resource: GitLabDiscussionResource,
        discussionID: String? = nil
    ) {
        self.accountID = accountID
        self.discussionID = discussionID

        switch resource {
        case let .issue(route):
            resourceKind = .issue
            projectID = route.projectID
            resourceIID = route.issueIID
        case let .mergeRequest(route):
            resourceKind = .mergeRequest
            projectID = route.projectID
            resourceIID =
                route.mergeRequestIID
        }
    }

    var resource: GitLabDiscussionResource {
        switch resourceKind {
        case .issue:
            .issue(
                GitLabIssueRoute(
                    projectID: projectID,
                    issueIID: resourceIID
                )
            )
        case .mergeRequest:
            .mergeRequest(
                GitLabMergeRequestRoute(
                    projectID: projectID,
                    mergeRequestIID: resourceIID
                )
            )
        }
    }

    var description: String {
        "GitLabDiscussionDraftKey(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var storageIdentifier: String {
        [
            accountID.storageIdentifier,
            resourceKind.rawValue,
            "\(projectID)",
            "\(resourceIID)",
            discussionID.map {
                "reply:\($0)"
            } ?? "comment",
        ]
        .map(Self.lengthPrefixed)
        .joined()
    }

    private static func lengthPrefixed(
        _ value: String
    ) -> String {
        "\(value.utf8.count):\(value)"
    }
}

nonisolated struct GitLabDiscussionDraft:
    Codable,
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let body: String
    let revision: Int

    var description: String {
        "GitLabDiscussionDraft(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated enum GitLabDiscussionDraftStoreError:
    Error,
    Equatable,
    Sendable
{
    case storage
}

nonisolated protocol GitLabDiscussionDraftStoring:
    Sendable
{
    func draft(
        for key: GitLabDiscussionDraftKey
    ) async -> GitLabDiscussionDraft?

    func store(
        _ draft: GitLabDiscussionDraft,
        for key: GitLabDiscussionDraftKey
    ) async throws(GitLabDiscussionDraftStoreError)

    func remove(
        for key: GitLabDiscussionDraftKey
    ) async

    func removeAll(
        for accountID: GitLabAccountID
    ) async
}

actor InMemoryGitLabDiscussionDraftStore:
    GitLabDiscussionDraftStoring
{
    private var drafts: [
        GitLabDiscussionDraftKey:
            GitLabDiscussionDraft
    ] = [:]

    func draft(
        for key: GitLabDiscussionDraftKey
    ) -> GitLabDiscussionDraft? {
        drafts[key]
    }

    func store(
        _ draft: GitLabDiscussionDraft,
        for key: GitLabDiscussionDraftKey
    ) throws(GitLabDiscussionDraftStoreError) {
        if
            let stored = drafts[key],
            stored.revision >= draft.revision
        {
            return
        }

        if draft.body.isEmpty {
            drafts.removeValue(forKey: key)
        } else {
            drafts[key] = draft
        }
    }

    func remove(
        for key: GitLabDiscussionDraftKey
    ) {
        drafts.removeValue(forKey: key)
    }

    func removeAll(
        for accountID: GitLabAccountID
    ) {
        drafts = drafts.filter {
            $0.key.accountID != accountID
        }
    }
}
