import Foundation

nonisolated struct GitLabAPIUser:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let username: String
    let name: String
    let avatarURL: URL?
    let webURL: URL?

    var summary: GitLabUserSummary {
        GitLabUserSummary(
            id: id,
            username: username,
            name: name,
            avatarURL: avatarURL
        )
    }

    var displayName: String {
        summary.displayName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case name
        case avatarURL = "avatar_url"
        case webURL = "web_url"
    }
}
