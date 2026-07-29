import Foundation

nonisolated struct GitLabIssueCreationDraftKey:
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let accountID: GitLabAccountID

    var description: String {
        "GitLabIssueCreationDraftKey(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var storageIdentifier: String {
        Self.lengthPrefixed(
            accountID.storageIdentifier
        )
    }

    static func lengthPrefixed(
        _ value: String
    ) -> String {
        "\(value.utf8.count):\(value)"
    }
}

nonisolated struct GitLabIssueCreationProjectSelection:
    Codable,
    Equatable,
    Identifiable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let id: Int
    let name: String
    let nameWithNamespace: String
    let pathWithNamespace: String

    init(
        id: Int,
        name: String,
        nameWithNamespace: String,
        pathWithNamespace: String
    ) {
        self.id = id
        self.name = name
        self.nameWithNamespace =
            nameWithNamespace
        self.pathWithNamespace =
            pathWithNamespace
    }

    init(project: GitLabProject) {
        self.init(
            id: project.id,
            name: project.name,
            nameWithNamespace:
                project.nameWithNamespace,
            pathWithNamespace:
                project.pathWithNamespace
        )
    }

    var description: String {
        "GitLabIssueCreationProjectSelection(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var isValid: Bool {
        id > 0
            && !name.trimmedForValidation.isEmpty
            && !nameWithNamespace
                .trimmedForValidation.isEmpty
            && !pathWithNamespace
                .trimmedForValidation.isEmpty
    }
}

nonisolated struct GitLabIssueCreationDraft:
    Codable,
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let selectedProject:
        GitLabIssueCreationProjectSelection?
    let title: String
    let rawDescription: String
    let labelNames: [String]
    let assigneeIDs: [Int]
    let confidential: Bool
    let dueDate: GitLabIssueDueDate?
    let revision: Int
    let pendingSubmissionFingerprint: String?

    private enum CodingKeys:
        String,
        CodingKey
    {
        case selectedProject
        case title
        case rawDescription = "description"
        case labelNames
        case assigneeIDs
        case confidential
        case dueDate
        case revision
        case pendingSubmissionFingerprint
    }

    init(
        selectedProject:
            GitLabIssueCreationProjectSelection? = nil,
        title: String = "",
        description: String = "",
        labelNames: [String] = [],
        assigneeIDs: [Int] = [],
        confidential: Bool = false,
        dueDate: GitLabIssueDueDate? = nil,
        revision: Int,
        pendingSubmissionFingerprint:
            String? = nil
    ) {
        self.selectedProject = selectedProject
        self.title = title
        rawDescription = description
        self.labelNames = labelNames
        self.assigneeIDs = assigneeIDs
        self.confidential = confidential
        self.dueDate = dueDate
        self.revision = revision
        self.pendingSubmissionFingerprint =
            pendingSubmissionFingerprint
    }

    var isPristine: Bool {
        selectedProject == nil
            && title.isEmpty
            && rawDescription.isEmpty
            && labelNames.isEmpty
            && assigneeIDs.isEmpty
            && !confidential
            && dueDate == nil
            && pendingSubmissionFingerprint == nil
    }

    var hasValidState: Bool {
        guard revision >= 0 else {
            return false
        }
        if
            let selectedProject,
            !selectedProject.isValid
        {
            return false
        }
        guard
            labelNames.allSatisfy({
                !$0.trimmedForValidation.isEmpty
            }),
            Set(labelNames).count
                == labelNames.count,
            assigneeIDs.allSatisfy({
                $0 > 0
            }),
            Set(assigneeIDs).count
                == assigneeIDs.count
        else {
            return false
        }
        if
            let dueDate,
            dueDate.apiValue == nil
        {
            return false
        }
        guard
            let pendingSubmissionFingerprint
        else {
            return true
        }
        return selectedProject != nil
            && !title.trimmedForValidation.isEmpty
            && Self.isSHA256HexDigest(
                pendingSubmissionFingerprint
            )
    }

    var description: String {
        "GitLabIssueCreationDraft(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    private static func isSHA256HexDigest(
        _ value: String
    ) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy {
                ($0 >= 48 && $0 <= 57)
                    || ($0 >= 97 && $0 <= 102)
            }
    }
}

nonisolated enum GitLabIssueCreationDraftStoreError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case storage

    var description: String {
        "Glab couldn’t securely save this issue draft."
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }
}

nonisolated protocol GitLabIssueCreationDraftStoring:
    Sendable
{
    func draft(
        for key: GitLabIssueCreationDraftKey
    ) async -> GitLabIssueCreationDraft?

    func store(
        _ draft: GitLabIssueCreationDraft,
        for key: GitLabIssueCreationDraftKey
    ) async throws(
        GitLabIssueCreationDraftStoreError
    )

    func remove(
        for key: GitLabIssueCreationDraftKey
    ) async

    func removeAll(
        for accountID: GitLabAccountID
    ) async
}

actor InMemoryGitLabIssueCreationDraftStore:
    GitLabIssueCreationDraftStoring
{
    private var drafts: [
        GitLabIssueCreationDraftKey:
            GitLabIssueCreationDraft
    ] = [:]

    func draft(
        for key: GitLabIssueCreationDraftKey
    ) -> GitLabIssueCreationDraft? {
        drafts[key]
    }

    func store(
        _ draft: GitLabIssueCreationDraft,
        for key: GitLabIssueCreationDraftKey
    ) throws(
        GitLabIssueCreationDraftStoreError
    ) {
        guard draft.hasValidState else {
            throw .storage
        }
        if
            let stored = drafts[key],
            stored.revision >= draft.revision
        {
            return
        }

        if draft.isPristine {
            drafts.removeValue(forKey: key)
        } else {
            drafts[key] = draft
        }
    }

    func remove(
        for key: GitLabIssueCreationDraftKey
    ) {
        drafts.removeValue(forKey: key)
    }

    func removeAll(
        for accountID: GitLabAccountID
    ) {
        drafts.removeValue(
            forKey:
                GitLabIssueCreationDraftKey(
                    accountID: accountID
                )
        )
    }
}

private nonisolated extension String {
    var trimmedForValidation: String {
        trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }
}
