import Foundation

nonisolated struct GitLabMergeRequestDiffFileID:
    Equatable,
    Hashable,
    Sendable
{
    let oldPath: String
    let newPath: String
}

nonisolated enum GitLabMergeRequestDiffAvailability:
    Equatable,
    Sendable
{
    case available
    case collapsed
    case tooLarge
    case missingText
}

nonisolated enum GitLabMergeRequestDiffFileKind:
    Equatable,
    Sendable
{
    case added
    case deleted
    case renamed
    case modified
}

nonisolated struct GitLabMergeRequestDiffFile:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let oldPath: String
    let newPath: String
    let oldMode: String?
    let newMode: String?
    let diff: String
    let isNewFile: Bool
    let isRenamedFile: Bool
    let isDeletedFile: Bool
    let isGeneratedFile: Bool
    let isCollapsed: Bool
    let isTooLarge: Bool

    var id: GitLabMergeRequestDiffFileID {
        GitLabMergeRequestDiffFileID(
            oldPath: oldPath,
            newPath: newPath
        )
    }

    var kind: GitLabMergeRequestDiffFileKind {
        if isNewFile {
            return .added
        }
        if isDeletedFile {
            return .deleted
        }
        if isRenamedFile {
            return .renamed
        }
        return .modified
    }

    var availability: GitLabMergeRequestDiffAvailability {
        if isTooLarge {
            return .tooLarge
        }
        if isCollapsed {
            return .collapsed
        }
        if diff.isEmpty {
            return .missingText
        }
        return .available
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        oldPath = try container.decode(
            String.self,
            forKey: .oldPath
        )
        newPath = try container.decode(
            String.self,
            forKey: .newPath
        )
        oldMode = try container.decodeIfPresent(
            String.self,
            forKey: .oldMode
        )
        newMode = try container.decodeIfPresent(
            String.self,
            forKey: .newMode
        )
        diff = try container.decodeIfPresent(
            String.self,
            forKey: .diff
        ) ?? ""
        isNewFile = try container.decodeIfPresent(
            Bool.self,
            forKey: .isNewFile
        ) ?? false
        isRenamedFile = try container.decodeIfPresent(
            Bool.self,
            forKey: .isRenamedFile
        ) ?? false
        isDeletedFile = try container.decodeIfPresent(
            Bool.self,
            forKey: .isDeletedFile
        ) ?? false
        isGeneratedFile = try container.decodeIfPresent(
            Bool.self,
            forKey: .isGeneratedFile
        ) ?? false
        isCollapsed = try container.decodeIfPresent(
            Bool.self,
            forKey: .isCollapsed
        ) ?? false
        isTooLarge = try container.decodeIfPresent(
            Bool.self,
            forKey: .isTooLarge
        ) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case oldPath = "old_path"
        case newPath = "new_path"
        case oldMode = "a_mode"
        case newMode = "b_mode"
        case diff
        case isNewFile = "new_file"
        case isRenamedFile = "renamed_file"
        case isDeletedFile = "deleted_file"
        case isGeneratedFile = "generated_file"
        case isCollapsed = "collapsed"
        case isTooLarge = "too_large"
    }
}
