import Foundation

nonisolated struct GitLabUserRoute:
    Equatable,
    Hashable,
    Sendable
{
    let id: Int
    let username: String
    let name: String
    let avatarURL: URL?

    init(
        id: Int,
        username: String,
        name: String,
        avatarURL: URL?
    ) {
        self.id = id
        self.username = username
        self.name = name
        self.avatarURL = avatarURL
    }

    init(user: GitLabAPIUser) {
        self.init(
            id: user.id,
            username: user.username,
            name: user.name,
            avatarURL: user.avatarURL
        )
    }

    init(user: GitLabUserSummary) {
        self.init(
            id: user.id,
            username: user.username,
            name: user.name,
            avatarURL: user.avatarURL
        )
    }

    var summary: GitLabUserSummary {
        GitLabUserSummary(
            id: id,
            username: username,
            name: name,
            avatarURL: avatarURL
        )
    }
}

nonisolated struct GitLabUserProfile:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let username: String
    let name: String
    let state: String?
    let isLocked: Bool
    let avatarURL: URL?
    let webURL: URL?
    let createdAt: Date?
    let bio: String?
    let isBot: Bool
    let location: String?
    let publicEmail: String?
    let linkedIn: String?
    let twitter: String?
    let discord: String?
    let github: String?
    let website: String?
    let organization: String?
    let jobTitle: String?
    let pronouns: String?
    let workInformation: String?
    var followers: Int?
    let following: Int?
    let localTime: String?
    var isFollowed: Bool?

    var summary: GitLabUserSummary {
        GitLabUserSummary(
            id: id,
            username: username,
            name: name,
            avatarURL: safeAvatarURL
        )
    }

    var displayName: String {
        summary.displayName
    }

    var safeAvatarURL: URL? {
        GitLabWebURL.validated(avatarURL)
    }

    var safeWebURL: URL? {
        GitLabWebURL.validated(webURL)
    }

    var contacts: [GitLabUserContact] {
        [
            GitLabUserContact.email(publicEmail),
            GitLabUserContact.website(website),
            GitLabUserContact.github(github),
            GitLabUserContact.linkedIn(linkedIn),
            GitLabUserContact.twitter(twitter),
            GitLabUserContact.discord(discord),
        ]
        .compactMap { $0 }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        id = try container.decode(Int.self, forKey: .id)
        username = try container.decode(
            String.self,
            forKey: .username
        )
        name = try container.decode(
            String.self,
            forKey: .name
        )
        state = container.nonemptyString(forKey: .state)
        isLocked = container.lossy(
            Bool.self,
            forKey: .isLocked
        ) ?? false
        avatarURL = container.lossy(
            URL.self,
            forKey: .avatarURL
        )
        webURL = container.lossy(
            URL.self,
            forKey: .webURL
        )
        createdAt = container.iso8601Date(
            forKey: .createdAt
        )
        bio = container.nonemptyString(forKey: .bio)
        isBot = container.lossy(
            Bool.self,
            forKey: .isBot
        ) ?? false
        location = container.nonemptyString(
            forKey: .location
        )
        publicEmail = container.nonemptyString(
            forKey: .publicEmail
        )
        linkedIn = container.nonemptyString(
            forKey: .linkedIn
        )
        twitter = container.nonemptyString(
            forKey: .twitter
        )
        discord = container.nonemptyString(
            forKey: .discord
        )
        github = container.nonemptyString(
            forKey: .github
        )
        website = container.nonemptyString(
            forKey: .website
        )
        organization = container.nonemptyString(
            forKey: .organization
        )
        jobTitle = container.nonemptyString(
            forKey: .jobTitle
        )
        pronouns = container.nonemptyString(
            forKey: .pronouns
        )
        workInformation = container.nonemptyString(
            forKey: .workInformation
        )
        followers = container.nonnegativeInt(
            forKey: .followers
        )
        following = container.nonnegativeInt(
            forKey: .following
        )
        localTime = container.nonemptyString(
            forKey: .localTime
        )
        isFollowed = container.lossy(
            Bool.self,
            forKey: .isFollowed
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case name
        case state
        case isLocked = "locked"
        case avatarURL = "avatar_url"
        case webURL = "web_url"
        case createdAt = "created_at"
        case bio
        case isBot = "bot"
        case location
        case publicEmail = "public_email"
        case linkedIn = "linkedin"
        case twitter
        case discord
        case github
        case website = "website_url"
        case organization
        case jobTitle = "job_title"
        case pronouns
        case workInformation = "work_information"
        case followers
        case following
        case localTime = "local_time"
        case isFollowed = "is_followed"
    }
}

nonisolated struct GitLabUserStatus:
    Decodable,
    Equatable,
    Sendable
{
    let emoji: String?
    let availability: String?
    let message: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        emoji = container.nonemptyString(forKey: .emoji)
        availability = container.nonemptyString(
            forKey: .availability
        )
        message = container.nonemptyString(
            forKey: .message
        )
    }

    private enum CodingKeys: String, CodingKey {
        case emoji
        case availability
        case message
    }
}

nonisolated struct GitLabUserGPGKey:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let key: String
    let createdAt: Date?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        id = try container.decode(Int.self, forKey: .id)
        key = try container.decode(
            String.self,
            forKey: .key
        )
        createdAt = container.iso8601Date(
            forKey: .createdAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case key
        case createdAt = "created_at"
    }
}

nonisolated struct GitLabUserContact:
    Equatable,
    Identifiable,
    Sendable
{
    enum Icon: Equatable, Sendable {
        case asset(String)
        case system(String)
    }

    enum ID: String, Sendable {
        case email
        case website
        case github
        case linkedIn
        case twitter
        case discord
    }

    let id: ID
    let title: String
    let value: String
    let icon: Icon
    let destination: URL?

    var showsTitle: Bool {
        if case .system = icon {
            true
        } else {
            false
        }
    }

    static func email(
        _ value: String?
    ) -> Self? {
        guard let value = normalized(value) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = value
        return Self(
            id: .email,
            title: "Email",
            value: value,
            icon: .system("envelope"),
            destination: components.url
        )
    }

    static func website(
        _ value: String?
    ) -> Self? {
        guard let value = normalized(value) else {
            return nil
        }
        return Self(
            id: .website,
            title: "Website",
            value: value,
            icon: .system("globe"),
            destination: secureURL(from: value)
        )
    }

    static func github(
        _ value: String?
    ) -> Self? {
        social(
            value,
            id: .github,
            title: "GitHub",
            icon: .asset("GitHubMark"),
            host: "github.com"
        )
    }

    static func linkedIn(
        _ value: String?
    ) -> Self? {
        social(
            value,
            id: .linkedIn,
            title: "LinkedIn",
            icon: .asset("LinkedInMark"),
            host: "www.linkedin.com",
            pathPrefix: "/in"
        )
    }

    static func twitter(
        _ value: String?
    ) -> Self? {
        social(
            value,
            id: .twitter,
            title: "X",
            icon: .asset("XMark"),
            host: "x.com"
        )
    }

    static func discord(
        _ value: String?
    ) -> Self? {
        guard let value = normalized(value) else {
            return nil
        }
        let identifier = value.trimmingCharacters(
            in: CharacterSet(charactersIn: "@/")
        )
        let destination = identifier.allSatisfy(\.isNumber)
            ? socialURL(
                host: "discord.com",
                path: "/users/\(identifier)"
            )
            : nil
        return Self(
            id: .discord,
            title: "Discord",
            value: value,
            icon: .asset("DiscordMark"),
            destination: destination
        )
    }

    private static func social(
        _ rawValue: String?,
        id: ID,
        title: String,
        icon: Icon,
        host: String,
        pathPrefix: String = ""
    ) -> Self? {
        guard let value = normalized(rawValue) else {
            return nil
        }
        let identifier = value.trimmingCharacters(
            in: CharacterSet(charactersIn: "@/")
        )
        let path = pathPrefix
            + "/"
            + identifier
        let destination = value.contains("://")
            ? secureURL(from: value)
            : socialURL(
                host: host,
                path: path
            )
        return Self(
            id: id,
            title: title,
            value: value,
            icon: icon,
            destination: destination
        )
    }

    private static func secureURL(
        from value: String
    ) -> URL? {
        let candidate = value.contains("://")
            ? value
            : "https://\(value)"
        return GitLabWebURL.validated(
            URL(string: candidate)
        )
    }

    private static func socialURL(
        host: String,
        path: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        return GitLabWebURL.validated(
            components.url
        )
    }

    private static func normalized(
        _ value: String?
    ) -> String? {
        let normalized = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalized?.isEmpty == false
            ? normalized
            : nil
    }
}

private nonisolated extension KeyedDecodingContainer {
    func lossy<Value: Decodable>(
        _ type: Value.Type,
        forKey key: Key
    ) -> Value? {
        try? decodeIfPresent(type, forKey: key)
    }

    func nonemptyString(
        forKey key: Key
    ) -> String? {
        guard
            let value = lossy(
                String.self,
                forKey: key
            )?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    func nonnegativeInt(
        forKey key: Key
    ) -> Int? {
        guard
            let value = lossy(
                Int.self,
                forKey: key
            ),
            value >= 0
        else {
            return nil
        }
        return value
    }

    func iso8601Date(
        forKey key: Key
    ) -> Date? {
        guard
            let value = lossy(
                String.self,
                forKey: key
            )
        else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = fractional.date(from: value) {
            return date
        }

        return ISO8601DateFormatter()
            .date(from: value)
    }
}
