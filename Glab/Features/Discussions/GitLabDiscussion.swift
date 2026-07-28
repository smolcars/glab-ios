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
    let baseSHA: String?
    let startSHA: String?
    let headSHA: String?
    let positionType: String?
    let oldPath: String?
    let newPath: String?
    let oldLine: Int?
    let newLine: Int?

    init(
        baseSHA: String? = nil,
        startSHA: String? = nil,
        headSHA: String? = nil,
        positionType: String? = nil,
        oldPath: String? = nil,
        newPath: String? = nil,
        oldLine: Int? = nil,
        newLine: Int? = nil
    ) {
        self.baseSHA = baseSHA
        self.startSHA = startSHA
        self.headSHA = headSHA
        self.positionType = positionType
        self.oldPath = oldPath
        self.newPath = newPath
        self.oldLine = oldLine
        self.newLine = newLine
    }

    var displayPath: String? {
        newPath ?? oldPath
    }

    var displayLine: Int? {
        newLine ?? oldLine
    }

    var versionIdentity:
        GitLabMergeRequestDiffVersionIdentity?
    {
        guard
            let baseSHA,
            let startSHA,
            let headSHA
        else {
            return nil
        }
        return GitLabMergeRequestDiffVersionIdentity(
            baseSHA: baseSHA,
            startSHA: startSHA,
            headSHA: headSHA
        )
    }

    var linePosition: GitLabDiffLinePosition? {
        guard
            positionType?
                .lowercased() == "text",
            let version = versionIdentity,
            let oldPath,
            let newPath
        else {
            return nil
        }
        return GitLabDiffLinePosition(
            version: version,
            oldPath: oldPath,
            newPath: newPath,
            oldLine: oldLine,
            newLine: newLine
        )
    }

    private enum CodingKeys: String, CodingKey {
        case baseSHA = "base_sha"
        case startSHA = "start_sha"
        case headSHA = "head_sha"
        case positionType = "position_type"
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
    let activityText: String?

    init(
        id: Int,
        type: String?,
        body: String,
        author: GitLabAPIUser,
        createdAt: Date,
        updatedAt: Date,
        system: Bool?,
        noteableID: Int,
        noteableType: String,
        projectID: Int,
        noteableIID: Int?,
        confidential: Bool?,
        internalNote: Bool?,
        resolvable: Bool?,
        resolved: Bool?,
        resolvedBy: GitLabAPIUser?,
        resolvedAt: Date?,
        position: GitLabDiscussionPosition?
    ) {
        self.id = id
        self.type = type
        self.body = body
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.system = system
        self.noteableID = noteableID
        self.noteableType = noteableType
        self.projectID = projectID
        self.noteableIID = noteableIID
        self.confidential = confidential
        self.internalNote = internalNote
        self.resolvable = resolvable
        self.resolved = resolved
        self.resolvedBy = resolvedBy
        self.resolvedAt = resolvedAt
        self.position = position
        activityText = system == true
            ? GitLabActivityTextNormalizer()
                .normalize(body)
            : nil
    }

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

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        self.init(
            id: try container.decode(
                Int.self,
                forKey: .id
            ),
            type:
                try container.decodeIfPresent(
                    String.self,
                    forKey: .type
                ),
            body: try container.decode(
                String.self,
                forKey: .body
            ),
            author: try container.decode(
                GitLabAPIUser.self,
                forKey: .author
            ),
            createdAt: try container.decode(
                Date.self,
                forKey: .createdAt
            ),
            updatedAt: try container.decode(
                Date.self,
                forKey: .updatedAt
            ),
            system:
                try container.decodeIfPresent(
                    Bool.self,
                    forKey: .system
                ),
            noteableID: try container.decode(
                Int.self,
                forKey: .noteableID
            ),
            noteableType: try container.decode(
                String.self,
                forKey: .noteableType
            ),
            projectID: try container.decode(
                Int.self,
                forKey: .projectID
            ),
            noteableIID:
                try container.decodeIfPresent(
                    Int.self,
                    forKey: .noteableIID
                ),
            confidential:
                try container.decodeIfPresent(
                    Bool.self,
                    forKey: .confidential
                ),
            internalNote:
                try container.decodeIfPresent(
                    Bool.self,
                    forKey: .internalNote
                ),
            resolvable:
                try container.decodeIfPresent(
                    Bool.self,
                    forKey: .resolvable
                ),
            resolved:
                try container.decodeIfPresent(
                    Bool.self,
                    forKey: .resolved
                ),
            resolvedBy:
                try container.decodeIfPresent(
                    GitLabAPIUser.self,
                    forKey: .resolvedBy
                ),
            resolvedAt:
                try container.decodeIfPresent(
                    Date.self,
                    forKey: .resolvedAt
                ),
            position:
                try container.decodeIfPresent(
                    GitLabDiscussionPosition.self,
                    forKey: .position
                )
        )
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

nonisolated struct GitLabDiscussionThreadResolution:
    Equatable,
    Sendable
{
    let discussionID: String
    let isResolved: Bool
    let resolvedBy: GitLabAPIUser?
    let resolvedAt: Date?
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

    var threadResolution:
        GitLabDiscussionThreadResolution?
    {
        guard
            !individualNote,
            let note = notes.first(
                where: \.isResolvable
            )
        else {
            return nil
        }
        let isResolved = note.isResolved
        return GitLabDiscussionThreadResolution(
            discussionID: id,
            isResolved: isResolved,
            resolvedBy:
                isResolved
                    ? note.resolvedBy
                    : nil,
            resolvedAt:
                isResolved
                    ? note.resolvedAt
                    : nil
        )
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
