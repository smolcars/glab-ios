import Foundation

nonisolated struct GitLabAuthenticatedUser: Decodable, Equatable, Sendable {
    let id: Int
    let username: String
    let name: String
    let avatarURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case name
        case avatarURL = "avatar_url"
    }
}
