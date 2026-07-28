import Foundation

nonisolated struct GitLabMergeRequestDiffVersionIdentity:
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let baseSHA: String
    let startSHA: String
    let headSHA: String

    init?(
        baseSHA: String,
        startSHA: String,
        headSHA: String
    ) {
        let baseSHA = baseSHA.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let startSHA = startSHA.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let headSHA = headSHA.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard
            !baseSHA.isEmpty,
            !startSHA.isEmpty,
            !headSHA.isEmpty
        else {
            return nil
        }

        self.baseSHA = baseSHA
        self.startSHA = startSHA
        self.headSHA = headSHA
    }

    var description: String {
        "GitLabMergeRequestDiffVersionIdentity(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated struct GitLabDiffLinePosition:
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let version:
        GitLabMergeRequestDiffVersionIdentity
    let oldPath: String
    let newPath: String
    let oldLine: Int?
    let newLine: Int?

    init?(
        version:
            GitLabMergeRequestDiffVersionIdentity,
        oldPath: String,
        newPath: String,
        oldLine: Int?,
        newLine: Int?
    ) {
        guard
            !oldPath.isEmpty,
            !newPath.isEmpty,
            oldLine.map({ $0 > 0 }) ?? true,
            newLine.map({ $0 > 0 }) ?? true,
            oldLine != nil || newLine != nil
        else {
            return nil
        }

        self.version = version
        self.oldPath = oldPath
        self.newPath = newPath
        self.oldLine = oldLine
        self.newLine = newLine
    }

    init?(
        version:
            GitLabMergeRequestDiffVersionIdentity,
        oldPath: String,
        newPath: String,
        line: GitLabDiffLine
    ) {
        let oldLine: Int?
        let newLine: Int?

        switch line.kind {
        case .addition:
            guard
                line.oldLineNumber == nil,
                line.newLineNumber != nil
            else {
                return nil
            }
            oldLine = nil
            newLine = line.newLineNumber
        case .deletion:
            guard
                line.oldLineNumber != nil,
                line.newLineNumber == nil
            else {
                return nil
            }
            oldLine = line.oldLineNumber
            newLine = nil
        case .context:
            guard
                line.oldLineNumber != nil,
                line.newLineNumber != nil
            else {
                return nil
            }
            oldLine = line.oldLineNumber
            newLine = line.newLineNumber
        }

        self.init(
            version: version,
            oldPath: oldPath,
            newPath: newPath,
            oldLine: oldLine,
            newLine: newLine
        )
    }

    var displayLine: Int {
        newLine ?? oldLine ?? 0
    }

    var description: String {
        "GitLabDiffLinePosition(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var storageIdentifier: String {
        [
            version.baseSHA,
            version.startSHA,
            version.headSHA,
            oldPath,
            newPath,
            oldLine.map(String.init) ?? "-",
            newLine.map(String.init) ?? "-",
        ]
        .map {
            "\($0.utf8.count):\($0)"
        }
        .joined()
    }
}
