import Foundation

nonisolated struct GitLabResourceEditDraftKey:
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let accountID: GitLabAccountID
    let target: GitLabResourceEditTarget

    var description: String {
        "GitLabResourceEditDraftKey(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var storageIdentifier: String {
        [
            accountID.storageIdentifier,
            target.kindStorageIdentifier,
            String(target.projectID),
            String(target.resourceIID),
        ]
        .map(Self.lengthPrefixed)
        .joined()
    }

    static func lengthPrefixed(
        _ value: String
    ) -> String {
        "\(value.utf8.count):\(value)"
    }
}

nonisolated struct GitLabResourceEditDraft:
    Codable,
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let baseline: GitLabResourceEditSnapshot
    let title: String
    let currentDescription: String
    let revision: Int
    let requiresDeliveryCheck: Bool

    private enum CodingKeys:
        String,
        CodingKey
    {
        case baseline
        case title
        case currentDescription = "description"
        case revision
        case requiresDeliveryCheck
    }

    init(
        baseline: GitLabResourceEditSnapshot,
        title: String,
        description: String,
        revision: Int,
        requiresDeliveryCheck: Bool = false
    ) {
        self.baseline = baseline
        self.title = title
        currentDescription = description
        self.revision = revision
        self.requiresDeliveryCheck =
            requiresDeliveryCheck
    }

    var isDirty: Bool {
        title != baseline.title
            || currentDescription
                != baseline.rawDescription
    }

    var hasConsistentDeliveryState: Bool {
        !requiresDeliveryCheck || isDirty
    }

    var description: String {
        "GitLabResourceEditDraft(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated enum GitLabResourceEditDraftStoreError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case storage

    var description: String {
        "Glab couldn’t securely save this edit draft."
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }
}

nonisolated protocol GitLabResourceEditDraftStoring:
    Sendable
{
    func draft(
        for key: GitLabResourceEditDraftKey
    ) async -> GitLabResourceEditDraft?

    func store(
        _ draft: GitLabResourceEditDraft,
        for key: GitLabResourceEditDraftKey
    ) async throws(
        GitLabResourceEditDraftStoreError
    )

    func remove(
        for key: GitLabResourceEditDraftKey
    ) async

    func removeAll(
        for accountID: GitLabAccountID
    ) async
}

actor InMemoryGitLabResourceEditDraftStore:
    GitLabResourceEditDraftStoring
{
    private var drafts: [
        GitLabResourceEditDraftKey:
            GitLabResourceEditDraft
    ] = [:]

    func draft(
        for key: GitLabResourceEditDraftKey
    ) -> GitLabResourceEditDraft? {
        drafts[key]
    }

    func store(
        _ draft: GitLabResourceEditDraft,
        for key: GitLabResourceEditDraftKey
    ) throws(
        GitLabResourceEditDraftStoreError
    ) {
        guard
            draft.baseline.target
                == key.target,
            draft.hasConsistentDeliveryState
        else {
            throw .storage
        }
        if
            let stored = drafts[key],
            stored.revision >= draft.revision
        {
            return
        }

        if draft.isDirty {
            drafts[key] = draft
        } else {
            drafts.removeValue(forKey: key)
        }
    }

    func remove(
        for key: GitLabResourceEditDraftKey
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
