import Foundation

nonisolated enum GitLabEmojiAwardable:
    Equatable,
    Hashable,
    Sendable
{
    case resource(GitLabDiscussionResource)
    case note(
        id: Int,
        in: GitLabDiscussionResource
    )

    var resource: GitLabDiscussionResource {
        switch self {
        case let .resource(resource),
             let .note(_, resource):
            resource
        }
    }

    var noteID: Int? {
        guard case let .note(id, _) = self else {
            return nil
        }
        return id
    }
}

nonisolated struct GitLabEmojiAward:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let name: String
    let user: GitLabAPIUser
    let createdAt: Date
    let updatedAt: Date
    let awardableID: Int
    let awardableType: String

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case user
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case awardableID = "awardable_id"
        case awardableType = "awardable_type"
    }
}

nonisolated struct GitLabEmojiPickerItem:
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    let name: String
    let display: String
    let title: String

    var id: String {
        name
    }

    static let common: [Self] = [
        Self(
            name: "thumbsup",
            display: "👍",
            title: "Thumbs up"
        ),
        Self(
            name: "thumbsdown",
            display: "👎",
            title: "Thumbs down"
        ),
        Self(
            name: "heart",
            display: "❤️",
            title: "Heart"
        ),
        Self(
            name: "tada",
            display: "🎉",
            title: "Celebrate"
        ),
        Self(
            name: "eyes",
            display: "👀",
            title: "Eyes"
        ),
        Self(
            name: "rocket",
            display: "🚀",
            title: "Rocket"
        ),
    ]

    static func item(
        named name: String
    ) -> Self? {
        common.first {
            $0.name == name
        }
    }

    static func display(
        for name: String
    ) -> String {
        if let item = item(named: name) {
            return item.display
        }

        let separators =
            CharacterSet
            .whitespacesAndNewlines
            .union(.controlCharacters)
        let normalized = name
            .replacingOccurrences(
                of: ":",
                with: ""
            )
            .components(
                separatedBy: separators
            )
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .prefix(32)
        guard !normalized.isEmpty else {
            return "Emoji"
        }
        return ":\(normalized):"
    }
}

nonisolated struct GitLabEmojiReactionGroup:
    Equatable,
    Identifiable,
    Sendable
{
    let name: String
    let display: String
    let count: Int
    let currentUserAwardIDs: [Int]
    let isPending: Bool
    let hasPendingCurrentUserAdd: Bool

    var id: String {
        name
    }

    var isSelectedByCurrentUser: Bool {
        hasPendingCurrentUserAdd
            || !currentUserAwardIDs.isEmpty
    }

    static func groups(
        awards: [GitLabEmojiAward],
        currentUserID: Int
    ) -> [Self] {
        var awardsByName:
            [String: [GitLabEmojiAward]] = [:]
        var orderedNames: [String] = []

        for award in awards {
            if awardsByName[award.name] == nil {
                orderedNames.append(award.name)
            }
            awardsByName[award.name, default: []]
                .append(award)
        }

        return orderedNames.compactMap { name in
            guard let groupedAwards =
                awardsByName[name]
            else {
                return nil
            }
            return Self(
                name: name,
                display:
                    GitLabEmojiPickerItem
                    .display(for: name),
                count: groupedAwards.count,
                currentUserAwardIDs:
                    groupedAwards
                    .filter {
                        $0.user.id
                            == currentUserID
                    }
                    .map(\.id),
                isPending: false,
                hasPendingCurrentUserAdd:
                    false
            )
        }
    }
}
