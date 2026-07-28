import Foundation

nonisolated struct GitLabCacheAccount:
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let host: GitLabHost
    let userID: Int

    init(
        host: GitLabHost,
        userID: Int
    ) {
        self.host = host
        self.userID = userID
    }

    init(session: GitLabStoredSession) {
        self.init(
            host: session.host,
            userID: session.user.id
        )
    }

    var description: String {
        "GitLabCacheAccount(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(host.siteURL)
        hasher.combine(userID)
    }

    var storageIdentifier: String {
        "\(host.siteURL.absoluteString)\n\(userID)"
    }
}

nonisolated struct GitLabResponseCacheKey:
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let account: GitLabCacheAccount
    let requestIdentifier: String

    init(
        account: GitLabCacheAccount,
        requestURL: URL
    ) {
        self.account = account
        requestIdentifier = Self.normalizedIdentifier(
            for: requestURL
        )
    }

    var description: String {
        "GitLabResponseCacheKey(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    private static func normalizedIdentifier(
        for url: URL
    ) -> String {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        components.user = nil
        components.password = nil
        components.queryItems = components.queryItems?.sorted {
            if $0.name == $1.name {
                return ($0.value ?? "") < ($1.value ?? "")
            }
            return $0.name < $1.name
        }

        return components.string ?? url.absoluteString
    }
}

nonisolated struct GitLabResponseCachePolicy:
    Equatable,
    Sendable
{
    let freshFor: TimeInterval
    let maximumAge: TimeInterval

    init(
        freshFor: TimeInterval,
        maximumAge: TimeInterval
    ) {
        self.freshFor = max(0, freshFor)
        self.maximumAge = max(
            self.freshFor,
            maximumAge
        )
    }
}

extension GitLabResponseCachePolicy {
    static let home = Self(
        freshFor: 60,
        maximumAge: 24 * 60 * 60
    )

    static let todos = Self(
        freshFor: 60,
        maximumAge: 24 * 60 * 60
    )

    static let workList = Self(
        freshFor: 2 * 60,
        maximumAge: 24 * 60 * 60
    )

    static let projects = Self(
        freshFor: 5 * 60,
        maximumAge: 24 * 60 * 60
    )

    static let workItemDetail = Self(
        freshFor: 5 * 60,
        maximumAge: 24 * 60 * 60
    )
}

nonisolated enum GitLabCachedResponseFreshness:
    Equatable,
    Sendable
{
    case fresh
    case stale
    case expired
}

nonisolated struct GitLabCachedResponse:
    Codable,
    Equatable,
    Sendable
{
    let body: Data
    let nextPageURL: URL?
    let totalCount: Int?
    let entityTag: String?
    let lastModified: String?
    let storedAt: Date
    let lastAccessedAt: Date

    func freshness(
        at date: Date,
        policy: GitLabResponseCachePolicy
    ) -> GitLabCachedResponseFreshness {
        let age = max(
            0,
            date.timeIntervalSince(storedAt)
        )

        if age <= policy.freshFor {
            return .fresh
        }
        if age <= policy.maximumAge {
            return .stale
        }
        return .expired
    }

    func accessed(at date: Date) -> Self {
        Self(
            body: body,
            nextPageURL: nextPageURL,
            totalCount: totalCount,
            entityTag: entityTag,
            lastModified: lastModified,
            storedAt: storedAt,
            lastAccessedAt: date
        )
    }
}

nonisolated enum GitLabResponseCacheError:
    Error,
    Equatable,
    Sendable
{
    case storage
}

nonisolated protocol GitLabResponseCaching: Sendable {
    func response(
        for key: GitLabResponseCacheKey
    ) async -> GitLabCachedResponse?

    func store(
        _ response: GitLabCachedResponse,
        for key: GitLabResponseCacheKey
    ) async throws(GitLabResponseCacheError)

    func remove(
        for key: GitLabResponseCacheKey
    ) async

    func removeAll(
        for account: GitLabCacheAccount
    ) async
}
