import Foundation

nonisolated struct GitLabAccountID:
    Codable,
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
        "GitLabAccountID(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var storageIdentifier: String {
        "\(host.siteURL.absoluteString)\n\(userID)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(host.siteURL)
        hasher.combine(userID)
    }
}

nonisolated struct GitLabAccountSummary:
    Codable,
    Equatable,
    Identifiable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let id: GitLabAccountID
    let user: GitLabUserSummary
    let credentialKind: GitLabCredentialKind
    let apiAccess: GitLabAPIAccess

    init(session: GitLabStoredSession) {
        id = GitLabAccountID(session: session)
        user = session.user
        credentialKind = session.credentialKind
        apiAccess = session.apiAccess
    }

    var host: GitLabHost {
        id.host
    }

    var description: String {
        "GitLabAccountSummary(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated enum GitLabAccountIndexError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case duplicateAccount
    case missingActiveAccount
    case unexpectedActiveAccount
    case unsupportedVersion

    var description: String {
        switch self {
        case .duplicateAccount:
            "The GitLab account index contains a duplicate account."
        case .missingActiveAccount:
            "The active GitLab account is missing from the account index."
        case .unexpectedActiveAccount:
            "An empty GitLab account index cannot have an active account."
        case .unsupportedVersion:
            "The GitLab account index uses an unsupported format."
        }
    }
}

nonisolated struct GitLabAccountIndex:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case accounts
        case activeAccountID
    }

    private static let currentFormatVersion = 1

    let accounts: [GitLabAccountSummary]
    let activeAccountID: GitLabAccountID?

    static var empty: Self {
        Self(
            validatedAccounts: [],
            activeAccountID: nil
        )
    }

    init(
        accounts: [GitLabAccountSummary],
        activeAccountID: GitLabAccountID?
    ) throws(GitLabAccountIndexError) {
        try Self.validate(
            accounts: accounts,
            activeAccountID: activeAccountID
        )
        self.init(
            validatedAccounts: accounts,
            activeAccountID: activeAccountID
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let formatVersion = try container.decode(
            Int.self,
            forKey: .formatVersion
        )
        guard formatVersion == Self.currentFormatVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .formatVersion,
                in: container,
                debugDescription:
                    GitLabAccountIndexError
                        .unsupportedVersion
                        .description
            )
        }

        let accounts = try container.decode(
            [GitLabAccountSummary].self,
            forKey: .accounts
        )
        let activeAccountID = try container.decodeIfPresent(
            GitLabAccountID.self,
            forKey: .activeAccountID
        )

        do {
            try self.init(
                accounts: accounts,
                activeAccountID: activeAccountID
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .accounts,
                in: container,
                debugDescription: error.description
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )
        try container.encode(
            Self.currentFormatVersion,
            forKey: .formatVersion
        )
        try container.encode(accounts, forKey: .accounts)
        try container.encodeIfPresent(
            activeAccountID,
            forKey: .activeAccountID
        )
    }

    func upserting(
        _ summary: GitLabAccountSummary,
        makeActive: Bool
    ) throws(GitLabAccountIndexError) -> Self {
        var updatedAccounts = accounts
        if let index = updatedAccounts.firstIndex(
            where: { $0.id == summary.id }
        ) {
            updatedAccounts[index] = summary
        } else {
            updatedAccounts.append(summary)
        }

        return try Self(
            accounts: updatedAccounts,
            activeAccountID:
                makeActive
                    ? summary.id
                    : activeAccountID
        )
    }

    func activating(
        _ accountID: GitLabAccountID
    ) throws(GitLabAccountIndexError) -> Self {
        try Self(
            accounts: accounts,
            activeAccountID: accountID
        )
    }

    func removing(
        _ accountID: GitLabAccountID
    ) throws(GitLabAccountIndexError) -> Self {
        let remaining = accounts.filter {
            $0.id != accountID
        }
        let nextActiveAccountID =
            activeAccountID == accountID
                ? remaining.first?.id
                : activeAccountID

        return try Self(
            accounts: remaining,
            activeAccountID: nextActiveAccountID
        )
    }

    private init(
        validatedAccounts: [GitLabAccountSummary],
        activeAccountID: GitLabAccountID?
    ) {
        accounts = validatedAccounts
        self.activeAccountID = activeAccountID
    }

    private static func validate(
        accounts: [GitLabAccountSummary],
        activeAccountID: GitLabAccountID?
    ) throws(GitLabAccountIndexError) {
        guard Set(accounts.map(\.id)).count == accounts.count else {
            throw .duplicateAccount
        }

        if accounts.isEmpty {
            guard activeAccountID == nil else {
                throw .unexpectedActiveAccount
            }
            return
        }

        guard
            let activeAccountID,
            accounts.contains(where: { $0.id == activeAccountID })
        else {
            throw .missingActiveAccount
        }
    }
}
