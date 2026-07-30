import Foundation

nonisolated enum GitLabUserReferenceSyntax {
    static let leadingBoundaryPattern =
        "(?<![A-Za-z0-9_./\\\\])"
    static let usernamePattern =
        "[A-Za-z0-9_]"
        + "(?:[A-Za-z0-9_.-]*"
        + "[A-Za-z0-9_])?"

    static func isUsernameInitial(
        _ character: Character
    ) -> Bool {
        isASCIILetter(character)
            || isASCIIDigit(character)
            || character == "_"
    }

    static func isUsernameBody(
        _ character: Character
    ) -> Bool {
        isUsernameInitial(character)
            || character == "."
            || character == "-"
    }

    static func allowsReference(
        after character: Character
    ) -> Bool {
        !isUsernameInitial(character)
            && character != "."
            && character != "/"
            && character != "\\"
    }

    private static func isASCIILetter(
        _ character: Character
    ) -> Bool {
        guard
            character.unicodeScalars.count == 1,
            let value =
                character.unicodeScalars
                    .first?.value
        else {
            return false
        }
        return
            (65 ... 90).contains(value)
            || (97 ... 122).contains(value)
    }

    private static func isASCIIDigit(
        _ character: Character
    ) -> Bool {
        guard
            character.unicodeScalars.count == 1,
            let value =
                character.unicodeScalars
                    .first?.value
        else {
            return false
        }
        return (48 ... 57).contains(value)
    }
}
