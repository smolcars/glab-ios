import Foundation

nonisolated enum GitLabRepositoryEntryType:
    Decodable,
    Equatable,
    Hashable,
    Sendable
{
    case tree
    case blob
    case commit
    case unknown(String)

    init(from decoder: any Decoder) throws {
        let value = try decoder
            .singleValueContainer()
            .decode(String.self)

        self = switch value {
        case "tree":
            .tree
        case "blob":
            .blob
        case "commit":
            .commit
        default:
            .unknown(value)
        }
    }
}

nonisolated struct GitLabRepositoryEntry:
    Decodable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    let id: String
    let name: String
    let type: GitLabRepositoryEntryType
    let path: String
    let mode: String

    var isDirectory: Bool {
        type == .tree
    }

    var isFile: Bool {
        type == .blob
    }

    var isSubmodule: Bool {
        type == .commit
    }

    var sortPriority: Int {
        switch type {
        case .tree:
            0
        case .blob:
            1
        case .commit:
            2
        case .unknown:
            3
        }
    }

    var systemImage: String {
        switch type {
        case .tree:
            "folder.fill"
        case .blob:
            "doc.text"
        case .commit:
            "shippingbox"
        case .unknown:
            "questionmark.square.dashed"
        }
    }
}

nonisolated struct GitLabRepositoryEntryPage:
    Equatable,
    Sendable
{
    let entries: [GitLabRepositoryEntry]
    let nextPageURL: URL?
}

nonisolated struct GitLabRepositoryBranch:
    Decodable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    let name: String
    let isDefault: Bool
    let isProtected: Bool
    let webURL: URL?

    var id: String {
        name
    }

    var safeWebURL: URL? {
        GitLabWebURL.validated(webURL)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case isDefault = "default"
        case isProtected = "protected"
        case webURL = "web_url"
    }
}

nonisolated struct GitLabRepositoryBranchPage:
    Equatable,
    Sendable
{
    let branches: [GitLabRepositoryBranch]
    let nextPageURL: URL?
}

nonisolated struct GitLabRepositorySearchResult:
    Decodable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    let blobID: String?
    let path: String
    let filename: String?
    let ref: String
    let startLine: Int?
    let projectID: Int

    var id: String {
        "\(ref):\(path)"
    }

    var displayName: String {
        filename?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).nilIfEmpty
            ?? URL(filePath: path).lastPathComponent
    }

    var parentPath: String {
        let parent = URL(filePath: path)
            .deletingLastPathComponent()
            .relativePath
        return parent == "." ? "" : parent
    }

    private enum CodingKeys: String, CodingKey {
        case blobID = "id"
        case path
        case filename
        case ref
        case startLine = "startline"
        case projectID = "project_id"
    }
}

nonisolated struct GitLabRepositorySearchPage:
    Equatable,
    Sendable
{
    let results: [GitLabRepositorySearchResult]
    let nextPageURL: URL?
}

nonisolated struct GitLabRepositoryFileRoute:
    Equatable,
    Hashable,
    Sendable
{
    let projectID: Int
    let projectWebURL: URL?
    let ref: String
    let path: String
    let blobID: String?

    init(
        projectID: Int,
        projectWebURL: URL?,
        ref: String,
        path: String,
        blobID: String?
    ) {
        self.projectID = projectID
        self.projectWebURL = projectWebURL
        self.ref = ref
        self.path = path
        self.blobID = blobID
    }

    init?(readmeIn project: GitLabProject) {
        guard
            let projectURL = project.safeWebURL,
            let readmeURL = project.safeReadmeURL,
            let ref = project.defaultBranch?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            !ref.isEmpty,
            Self.matchesOrigin(
                readmeURL,
                projectURL
            ),
            let projectPath = Self.decodedPath(
                of: projectURL
            ),
            let readmePath = Self.decodedPath(
                of: readmeURL
            )
        else {
            return nil
        }

        let currentMarker =
            projectPath + "/-/blob/" + ref + "/"
        let legacyMarker =
            projectPath + "/blob/" + ref + "/"
        let marker: String
        if readmePath.hasPrefix(currentMarker) {
            marker = currentMarker
        } else if readmePath.hasPrefix(legacyMarker) {
            marker = legacyMarker
        } else {
            return nil
        }

        let path = String(
            readmePath.dropFirst(marker.count)
        )
        guard Self.isSafeRepositoryPath(path) else {
            return nil
        }

        self.init(
            projectID: project.id,
            projectWebURL: projectURL,
            ref: ref,
            path: path,
            blobID: nil
        )
    }

    var fileName: String {
        URL(filePath: path).lastPathComponent
    }

    var parentPath: String {
        let parent = URL(filePath: path)
            .deletingLastPathComponent()
            .relativePath
        return parent == "." ? "" : parent
    }

    var safeWebURL: URL? {
        guard
            let projectWebURL = GitLabWebURL
                .validated(projectWebURL)
        else {
            return nil
        }

        return projectWebURL
            .appending(path: "-")
            .appending(path: "blob")
            .appending(path: ref)
            .appending(path: path)
    }

    var markdownResourceID:
        GitLabMarkdownResourceID
    {
        .repositoryFile(
            projectID: projectID,
            ref: ref,
            path: path,
            blobID: blobID
        )
    }

    private static func matchesOrigin(
        _ lhs: URL,
        _ rhs: URL
    ) -> Bool {
        guard
            let lhs = URLComponents(
                url: lhs,
                resolvingAgainstBaseURL: false
            ),
            let rhs = URLComponents(
                url: rhs,
                resolvingAgainstBaseURL: false
            )
        else {
            return false
        }
        return
            lhs.scheme?.lowercased()
                == rhs.scheme?.lowercased()
            && lhs.host?.lowercased()
                == rhs.host?.lowercased()
            && (lhs.port ?? 443)
                == (rhs.port ?? 443)
    }

    private static func decodedPath(
        of url: URL
    ) -> String? {
        URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?
        .percentEncodedPath
        .removingPercentEncoding
    }

    private static func isSafeRepositoryPath(
        _ path: String
    ) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.split(
                separator: "/",
                omittingEmptySubsequences: false
            ).contains {
                $0.isEmpty
                    || $0 == "."
                    || $0 == ".."
            }
    }
}

nonisolated enum GitLabRepositoryFilePresentation:
    CaseIterable,
    Equatable,
    Hashable,
    Sendable
{
    case rendered
    case raw

    var title: String {
        switch self {
        case .rendered:
            "Rendered"
        case .raw:
            "Raw"
        }
    }

    var systemImage: String {
        switch self {
        case .rendered:
            "doc.richtext"
        case .raw:
            "text.page"
        }
    }

    static let maximumRenderedMarkdownByteCount =
        1_024 * 1_024

    static func supportsRenderedMarkdown(
        _ document: GitLabSourceDocument
    ) -> Bool {
        document.language == .markdown
            && document.source.utf8.count
                <= maximumRenderedMarkdownByteCount
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
