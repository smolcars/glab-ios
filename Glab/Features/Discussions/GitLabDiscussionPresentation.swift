import Foundation

nonisolated struct GitLabDiscussionPresentation:
    Equatable,
    Sendable
{
    let activityNotes:
        [GitLabDiscussionNote]
    let conversations:
        [GitLabDiscussion]
    let paginationAnchor:
        GitLabDiscussion?

    init(
        discussions: [GitLabDiscussion]
    ) {
        var activityNotes:
            [GitLabDiscussionNote] = []
        var conversations:
            [GitLabDiscussion] = []
        activityNotes.reserveCapacity(
            discussions.count
        )
        conversations.reserveCapacity(
            discussions.count
        )

        for discussion in discussions {
            if discussion.isSystemActivity {
                activityNotes.append(
                    contentsOf:
                        discussion.notes
                )
            } else {
                conversations.append(
                    discussion
                )
            }
        }

        self.activityNotes = activityNotes
        self.conversations = conversations
        paginationAnchor =
            discussions.last
    }
}

nonisolated struct GitLabActivityTextNormalizer:
    Equatable,
    Sendable
{
    let maximumSourceLength: Int
    let maximumOutputLength: Int

    init(
        maximumSourceLength: Int = 32_768,
        maximumOutputLength: Int = 8_192
    ) {
        self.maximumSourceLength = max(
            0,
            maximumSourceLength
        )
        self.maximumOutputLength = max(
            0,
            maximumOutputLength
        )
    }

    func normalize(
        _ source: String
    ) -> String {
        let characters = Array(
            source.prefix(
                maximumSourceLength
            )
        )
        var output = Output(
            limit:
                maximumOutputLength
        )
        var index = 0

        while
            index < characters.count,
            !output.isFull
        {
            let character =
                characters[index]

            if
                character == "<",
                let tag = tag(
                    in: characters,
                    startingAt: index
                )
            {
                if tag.startsListItem {
                    output.appendListSeparator()
                } else if tag.insertsSpace {
                    output.appendWhitespace()
                }
                index = tag.endIndex + 1
                continue
            }

            if
                character == "&",
                let entity = entity(
                    in: characters,
                    startingAt: index
                )
            {
                output.append(entity.character)
                index =
                    entity.endIndex + 1
                continue
            }

            output.append(character)
            index += 1
        }

        let normalized = output.value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        return normalized.isEmpty
            ? "Activity details unavailable"
            : normalized
    }

    private func tag(
        in characters: [Character],
        startingAt start: Int
    ) -> Tag? {
        let maximumEnd = min(
            characters.count,
            start + 129
        )
        guard
            let end = (
                (start + 1)..<maximumEnd
            ).first(
                where: {
                    characters[$0] == ">"
                }
            )
        else {
            return nil
        }

        let raw = String(
            characters[(start + 1)..<end]
        )
        .trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var name = raw
        if
            name.first == "/"
                || name.first == "!"
                || name.first == "?"
        {
            name.removeFirst()
        }
        name = String(
            name.prefix {
                $0.isLetter
            }
        )
        .lowercased()
        guard !name.isEmpty else {
            return nil
        }

        return Tag(
            name: name,
            isClosing:
                raw.first == "/",
            endIndex: end
        )
    }

    private func entity(
        in characters: [Character],
        startingAt start: Int
    ) -> Entity? {
        let maximumEnd = min(
            characters.count,
            start + 14
        )
        guard
            let end = (
                (start + 1)..<maximumEnd
            ).first(
                where: {
                    characters[$0] == ";"
                }
            )
        else {
            return nil
        }
        let value = String(
            characters[(start + 1)..<end]
        )
        guard
            let character =
                Self.decodedEntity(value)
        else {
            return nil
        }
        return Entity(
            character: character,
            endIndex: end
        )
    }

    private static func decodedEntity(
        _ value: String
    ) -> Character? {
        switch value.lowercased() {
        case "amp":
            return "&"
        case "lt":
            return "<"
        case "gt":
            return ">"
        case "quot":
            return "\""
        case "apos", "#39":
            return "'"
        case "nbsp":
            return " "
        default:
            break
        }

        let number: UInt32?
        if value.hasPrefix("#x")
            || value.hasPrefix("#X")
        {
            number = UInt32(
                value.dropFirst(2),
                radix: 16
            )
        } else if value.hasPrefix("#") {
            number = UInt32(
                value.dropFirst()
            )
        } else {
            number = nil
        }
        guard
            let number,
            let scalar =
                Unicode.Scalar(number)
        else {
            return nil
        }
        return Character(
            String(scalar)
        )
    }

    private struct Tag {
        let name: String
        let isClosing: Bool
        let endIndex: Int

        var startsListItem: Bool {
            name == "li"
                && !isClosing
        }

        var insertsSpace: Bool {
            [
                "br",
                "div",
                "p",
                "ul",
                "ol",
            ].contains(name)
        }
    }

    private struct Entity {
        let character: Character
        let endIndex: Int
    }

    private struct Output {
        let limit: Int
        private(set) var characters:
            [Character] = []
        private var hasPendingWhitespace =
            false

        init(limit: Int) {
            self.limit = limit
            characters.reserveCapacity(
                min(limit, 512)
            )
        }

        var value: String {
            String(characters)
        }

        var isFull: Bool {
            characters.count >= limit
        }

        mutating func append(
            _ character: Character
        ) {
            if character.isWhitespace {
                appendWhitespace()
                return
            }
            appendPendingWhitespace()
            appendDirect(character)
        }

        mutating func appendWhitespace() {
            if !characters.isEmpty {
                hasPendingWhitespace = true
            }
        }

        mutating func appendListSeparator() {
            guard !characters.isEmpty else {
                return
            }
            hasPendingWhitespace = false
            while
                characters.last?
                    .isWhitespace == true
            {
                characters.removeLast()
            }
            guard
                limit - characters.count
                    >= 3
            else {
                return
            }
            characters.append(" ")
            characters.append("•")
            characters.append(" ")
        }

        private mutating func
            appendPendingWhitespace()
        {
            guard
                hasPendingWhitespace,
                !characters.isEmpty,
                characters.count < limit
            else {
                hasPendingWhitespace = false
                return
            }
            characters.append(" ")
            hasPendingWhitespace = false
        }

        private mutating func appendDirect(
            _ character: Character
        ) {
            guard characters.count < limit else {
                return
            }
            characters.append(character)
        }
    }
}

nonisolated enum
    GitLabDiscussionComposerLaunchDecision:
    Equatable,
    Sendable
{
    case present(
        GitLabDiscussionComposerTarget
    )
    case explainReadOnly
}

nonisolated enum GitLabDiscussionComposerLaunchPolicy {
    static func decision(
        for target:
            GitLabDiscussionComposerTarget,
        apiAccess: GitLabAPIAccess
    ) -> GitLabDiscussionComposerLaunchDecision {
        apiAccess.canWrite
            ? .present(target)
            : .explainReadOnly
    }
}
