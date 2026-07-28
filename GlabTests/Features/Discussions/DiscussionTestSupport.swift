import Foundation
@testable import Glab

func makeTestDiscussion(
    id: String = "discussion-1",
    individualNote: Bool = false,
    notes: [GitLabDiscussionNote]? = nil
) -> GitLabDiscussion {
    GitLabDiscussion(
        id: id,
        individualNote: individualNote,
        notes:
            notes
            ?? [
                makeTestDiscussionNote(),
            ]
    )
}

func makeTestDiscussionNote(
    id: Int = 101,
    body: String = "A **Markdown** comment",
    authorID: Int = 1,
    username: String = "reviewer",
    createdAt: Date = Date(
        timeIntervalSince1970: 1_000
    ),
    updatedAt: Date = Date(
        timeIntervalSince1970: 1_000
    ),
    system: Bool? = false,
    internalNote: Bool? = false,
    resolvable: Bool? = false,
    resolved: Bool? = false
) -> GitLabDiscussionNote {
    GitLabDiscussionNote(
        id: id,
        type: nil,
        body: body,
        author: GitLabAPIUser(
            id: authorID,
            username: username,
            name: username.capitalized,
            avatarURL: nil,
            webURL: URL(
                string:
                    "https://gitlab.example.com/\(username)"
            )
        ),
        createdAt: createdAt,
        updatedAt: updatedAt,
        system: system,
        noteableID: 501,
        noteableType: "Issue",
        projectID: 42,
        noteableIID: 7,
        confidential: false,
        internalNote: internalNote,
        resolvable: resolvable,
        resolved: resolved,
        resolvedBy: nil,
        resolvedAt: nil,
        position: nil
    )
}
