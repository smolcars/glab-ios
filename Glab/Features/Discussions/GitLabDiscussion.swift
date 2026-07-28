import Foundation

nonisolated enum GitLabDiscussionCommentBodyError:
    Error,
    Equatable,
    Sendable
{
    case empty
}

nonisolated struct GitLabDiscussionCommentBody:
    Encodable,
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let body: String

    init(
        _ body: String
    ) throws(GitLabDiscussionCommentBodyError) {
        guard
            !body.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            throw .empty
        }
        self.body = body
    }

    var description: String {
        "GitLabDiscussionCommentBody(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated enum GitLabDiscussionResource:
    Equatable,
    Hashable,
    Sendable
{
    case issue(GitLabIssueRoute)
    case mergeRequest(GitLabMergeRequestRoute)

    func markdownResourceID(
        noteID: Int
    ) -> GitLabMarkdownResourceID {
        switch self {
        case let .issue(route):
            .issueNote(
                projectID: route.projectID,
                issueIID: route.issueIID,
                noteID: noteID
            )
        case let .mergeRequest(route):
            .mergeRequestNote(
                projectID: route.projectID,
                mergeRequestIID:
                    route.mergeRequestIID,
                noteID: noteID
            )
        }
    }
}

nonisolated enum GitLabDiscussionNoteKind:
    Equatable,
    Sendable
{
    case individual
    case discussion
    case diff
    case unknown(String)
}

nonisolated struct GitLabDiscussionPosition:
    Decodable,
    Equatable,
    Sendable
{
    let oldPath: String?
    let newPath: String?
    let oldLine: Int?
    let newLine: Int?

    var displayPath: String? {
        newPath ?? oldPath
    }

    var displayLine: Int? {
        newLine ?? oldLine
    }

    private enum CodingKeys: String, CodingKey {
        case oldPath = "old_path"
        case newPath = "new_path"
        case oldLine = "old_line"
        case newLine = "new_line"
    }
}

nonisolated struct GitLabDiscussionNote:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let type: String?
    let body: String
    let author: GitLabAPIUser
    let createdAt: Date
    let updatedAt: Date
    let system: Bool?
    let noteableID: Int
    let noteableType: String
    let projectID: Int
    let noteableIID: Int?
    let confidential: Bool?
    let internalNote: Bool?
    let resolvable: Bool?
    let resolved: Bool?
    let resolvedBy: GitLabAPIUser?
    let resolvedAt: Date?
    let position: GitLabDiscussionPosition?

    var kind: GitLabDiscussionNoteKind {
        guard let type else {
            return .individual
        }

        switch type.lowercased() {
        case "discussionnote":
            return .discussion
        case "diffnote":
            return .diff
        default:
            return .unknown(type)
        }
    }

    var isSystem: Bool {
        system == true
    }

    var isInternal: Bool {
        internalNote == true
            || confidential == true
    }

    var isResolvable: Bool {
        resolvable == true
    }

    var isResolved: Bool {
        resolved == true
    }

    var isEdited: Bool {
        updatedAt != createdAt
    }

    var showsEditedStatus: Bool {
        !isSystem && isEdited
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case body
        case author
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case system
        case noteableID = "noteable_id"
        case noteableType = "noteable_type"
        case projectID = "project_id"
        case noteableIID = "noteable_iid"
        case confidential
        case internalNote = "internal"
        case resolvable
        case resolved
        case resolvedBy = "resolved_by"
        case resolvedAt = "resolved_at"
        case position
    }
}

nonisolated struct GitLabDiscussion:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: String
    let individualNote: Bool
    let notes: [GitLabDiscussionNote]

    var isSystemActivity: Bool {
        !notes.isEmpty
            && notes.allSatisfy(\.isSystem)
    }

    func reconciling(
        _ note: GitLabDiscussionNote
    ) -> Self {
        var reconciledNotes = notes
        if
            let index = reconciledNotes
                .firstIndex(
                    where: {
                        $0.id == note.id
                    }
                )
        {
            reconciledNotes[index] = note
        } else {
            reconciledNotes.append(note)
        }

        return Self(
            id: id,
            individualNote: individualNote,
            notes: reconciledNotes
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case individualNote = "individual_note"
        case notes
    }
}
