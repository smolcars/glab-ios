import Foundation

nonisolated struct GitLabProjectMember:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let username: String
    let name: String
    let state: String
    let avatarURL: URL?
    let webURL: URL?
    let accessLevel: Int

    var isActive: Bool {
        state.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        .lowercased() == "active"
    }

    var summary: GitLabUserSummary {
        GitLabUserSummary(
            id: id,
            username: username,
            name: name,
            avatarURL: avatarURL
        )
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case username
        case name
        case state
        case avatarURL = "avatar_url"
        case webURL = "web_url"
        case accessLevel = "access_level"
    }
}
