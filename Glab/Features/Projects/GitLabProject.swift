import Foundation

nonisolated struct GitLabProjectRoute:
    Equatable,
    Hashable,
    Sendable
{
    let pathWithNamespace: String
}

nonisolated enum GitLabProjectListMode:
    String,
    Equatable,
    Hashable,
    Sendable
{
    case recent
    case starred

    var filterName: String {
        switch self {
        case .recent:
            "membership"
        case .starred:
            "starred"
        }
    }

    var title: String {
        switch self {
        case .recent:
            "Recent Projects"
        case .starred:
            "Starred Projects"
        }
    }

    var emptyTitle: String {
        switch self {
        case .recent:
            "No recent projects"
        case .starred:
            "No starred projects"
        }
    }

    var emptyMessage: String {
        switch self {
        case .recent:
            "Projects you belong to will appear here."
        case .starred:
            "Projects you star will appear here."
        }
    }

    var systemImage: String {
        switch self {
        case .recent:
            "clock"
        case .starred:
            "star"
        }
    }
}

nonisolated enum GitLabProjectVisibility:
    Decodable,
    Equatable,
    Sendable
{
    case privateAccess
    case internalAccess
    case publicAccess
    case unknown(String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        self = switch value {
        case "private":
            .privateAccess
        case "internal":
            .internalAccess
        case "public":
            .publicAccess
        default:
            .unknown(value)
        }
    }

    var title: String {
        switch self {
        case .privateAccess:
            "Private"
        case .internalAccess:
            "Internal"
        case .publicAccess:
            "Public"
        case let .unknown(value):
            value.isEmpty ? "Unknown" : value.capitalized
        }
    }

    var systemImage: String {
        switch self {
        case .privateAccess:
            "lock.fill"
        case .internalAccess:
            "shield.lefthalf.filled"
        case .publicAccess:
            "globe"
        case .unknown:
            "questionmark.circle"
        }
    }
}

nonisolated struct GitLabProjectNamespace:
    Decodable,
    Equatable,
    Sendable
{
    let id: Int
    let name: String
    let path: String
    let kind: String
    let fullPath: String

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case kind
        case fullPath = "full_path"
    }
}

nonisolated struct GitLabProject:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let name: String
    let nameWithNamespace: String
    let pathWithNamespace: String
    let webURL: URL?
    let avatarURL: URL?
    let starCount: Int
    let lastActivityAt: Date
    let visibility: GitLabProjectVisibility
    let namespace: GitLabProjectNamespace?

    var safeWebURL: URL? {
        GitLabWebURL.validated(webURL)
    }

    var safeAvatarURL: URL? {
        GitLabWebURL.validated(avatarURL)
    }

    var namespaceTitle: String {
        if let fullPath = namespace?.fullPath.trimmedNonempty {
            return fullPath
        }

        let components = pathWithNamespace.split(separator: "/")
        guard components.count > 1 else {
            return "Project"
        }
        return components.dropLast().joined(separator: "/")
    }

    var avatarMark: String {
        let components = name.components(
            separatedBy: CharacterSet.alphanumerics.inverted
        )
        .filter { !$0.isEmpty }

        guard let first = components.first else {
            return "GL"
        }
        guard let last = components.dropFirst().last else {
            return String(first.prefix(2)).uppercased()
        }

        return (
            String(first.prefix(1))
                + String(last.prefix(1))
        )
        .uppercased()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameWithNamespace = "name_with_namespace"
        case pathWithNamespace = "path_with_namespace"
        case webURL = "web_url"
        case avatarURL = "avatar_url"
        case starCount = "star_count"
        case lastActivityAt = "last_activity_at"
        case visibility
        case namespace
    }
}

nonisolated struct GitLabProjectPage:
    Equatable,
    Sendable
{
    let projects: [GitLabProject]
    let nextPageURL: URL?
}

private nonisolated extension String {
    var trimmedNonempty: String? {
        let value = trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return value.isEmpty ? nil : value
    }
}
