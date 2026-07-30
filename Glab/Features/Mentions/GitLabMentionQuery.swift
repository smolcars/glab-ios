import Foundation

nonisolated struct GitLabMentionQuery:
    Equatable
{
    let query: String
    let replacementRange:
        Range<String.Index>

    static func active(
        in text: String,
        selection:
            Range<String.Index>?
    ) -> Self? {
        guard
            let selection,
            selection.isEmpty
        else {
            return nil
        }

        let cursor = selection.lowerBound
        var usernameStart = cursor
        while usernameStart > text.startIndex {
            let previous =
                text.index(
                    before: usernameStart
                )
            guard
                GitLabUserReferenceSyntax
                    .isUsernameBody(
                        text[previous]
                    )
            else {
                break
            }
            usernameStart = previous
        }

        guard usernameStart > text.startIndex else {
            return nil
        }
        let atSign =
            text.index(before: usernameStart)
        guard text[atSign] == "@" else {
            return nil
        }
        if atSign > text.startIndex {
            let preceding =
                text[
                    text.index(before: atSign)
                ]
            guard
                GitLabUserReferenceSyntax
                    .allowsReference(
                        after: preceding
                    )
            else {
                return nil
            }
        }

        let query =
            String(
                text[
                    usernameStart ..< cursor
                ]
            )
        if
            let first = query.first,
            !GitLabUserReferenceSyntax
                .isUsernameInitial(first)
        {
            return nil
        }

        var usernameEnd = cursor
        while usernameEnd < text.endIndex {
            guard
                GitLabUserReferenceSyntax
                    .isUsernameBody(
                        text[usernameEnd]
                    )
            else {
                break
            }
            usernameEnd =
                text.index(after: usernameEnd)
        }

        return Self(
            query: query,
            replacementRange:
                atSign ..< usernameEnd
        )
    }

    func inserting(
        username: String,
        into text: String
    ) -> GitLabMentionInsertion? {
        guard
            Self.isValidUsername(username)
        else {
            return nil
        }

        let startOffset =
            text.distance(
                from: text.startIndex,
                to: replacementRange
                    .lowerBound
            )
        let mention = "@\(username)"
        let suffix =
            text[replacementRange.upperBound...]
        let trailingSpace =
            suffix.isEmpty ? " " : ""
        var result = text
        result.replaceSubrange(
            replacementRange,
            with: mention + trailingSpace
        )

        return GitLabMentionInsertion(
            text: result,
            cursorCharacterOffset:
                startOffset
                + mention.count
                + trailingSpace.count
        )
    }

    private static func isValidUsername(
        _ username: String
    ) -> Bool {
        guard
            let first = username.first,
            let last = username.last,
            GitLabUserReferenceSyntax
                .isUsernameInitial(first),
            GitLabUserReferenceSyntax
                .isUsernameInitial(last)
        else {
            return false
        }
        return username.allSatisfy {
            GitLabUserReferenceSyntax
                .isUsernameBody($0)
        }
    }
}

nonisolated struct GitLabMentionInsertion:
    Equatable
{
    let text: String
    let cursorCharacterOffset: Int

    var cursor: String.Index {
        text.index(
            text.startIndex,
            offsetBy: cursorCharacterOffset
        )
    }
}
