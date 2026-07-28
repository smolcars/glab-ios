import Foundation

nonisolated struct GitLabDiscussionDraftKey:
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    private enum Target:
        Equatable,
        Hashable,
        Sendable
    {
        case newDiscussion
        case newDiffDiscussion(
            GitLabDiffLinePosition
        )
        case reply(String)
    }

    private enum ResourceKind:
        String,
        Sendable
    {
        case issue
        case mergeRequest
    }

    let accountID: GitLabAccountID

    private let resourceKind: ResourceKind
    private let projectID: Int
    private let resourceIID: Int
    private let target: Target

    init(
        accountID: GitLabAccountID,
        resource: GitLabDiscussionResource,
        target:
            GitLabDiscussionComposerTarget =
                .newDiscussion
    ) {
        self.accountID = accountID
        self.target =
            switch target {
            case .newDiscussion:
                .newDiscussion
            case let .newDiffDiscussion(
                position
            ):
                .newDiffDiscussion(position)
            case let .reply(discussionID):
                .reply(discussionID)
            }

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
            targetStorageIdentifier,
        ]
        .map(Self.lengthPrefixed)
        .joined()
    }

    private var targetStorageIdentifier:
        String
    {
        switch target {
        case .newDiscussion:
            "comment"
        case let .newDiffDiscussion(position):
            "diff:\(position.storageIdentifier)"
        case let .reply(discussionID):
            "reply:\(discussionID)"
        }
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
