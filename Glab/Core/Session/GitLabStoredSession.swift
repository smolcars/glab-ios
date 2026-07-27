import Foundation

nonisolated struct GitLabUserSummary: Codable, Equatable, Sendable {
    let id: Int
    let username: String
    let name: String
    let avatarURL: URL?

    var displayName: String {
        let normalizedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !normalizedName.isEmpty {
            return normalizedName
        }

        let normalizedUsername = username.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalizedUsername.isEmpty ? "GitLab user" : normalizedUsername
    }

    var avatarInitial: String {
        displayName.first.map { String($0).uppercased() } ?? "?"
    }
}

nonisolated enum GitLabStoredSessionError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case missingOAuthApplicationID
    case unexpectedOAuthApplicationID
    case missingPersonalAccessTokenMetadata
    case unexpectedPersonalAccessTokenMetadata
    case insufficientPersonalAccessTokenScope

    var description: String {
        switch self {
        case .missingOAuthApplicationID:
            "An OAuth session requires the GitLab host's application ID."
        case .unexpectedOAuthApplicationID:
            "A personal access token session cannot include an OAuth application ID."
        case .missingPersonalAccessTokenMetadata:
            "A personal access token session requires its scope and expiry metadata."
        case .unexpectedPersonalAccessTokenMetadata:
            "An OAuth session cannot include personal access token metadata."
        case .insufficientPersonalAccessTokenScope:
            "A personal access token session requires the api or read_api scope."
        }
    }
}

nonisolated struct GitLabStoredSession:
    Codable,
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    private enum CodingKeys: String, CodingKey {
        case host
        case user
        case oauthApplicationID
        case personalAccessTokenMetadata
        case credential
    }

    let host: GitLabHost
    let user: GitLabUserSummary
    let oauthApplicationID: String?
    let personalAccessTokenMetadata: GitLabPersonalAccessTokenMetadata?
    let credential: GitLabCredential

    var credentialKind: GitLabCredentialKind {
        credential.kind
    }

    var oauthExpiresAt: Date? {
        credential.oauthExpiresAt
    }

    var canRefreshOAuth: Bool {
        credential.canRefreshOAuth
    }

    var apiAccess: GitLabAPIAccess {
        personalAccessTokenMetadata?.apiAccess ?? .readWrite
    }

    var personalAccessTokenExpiresOn: String? {
        personalAccessTokenMetadata?.expiresOn
    }

    var description: String {
        "GitLabStoredSession(host: \(host.siteURL.absoluteString), "
            + "username: \(user.username), "
            + "oauthApplicationID: \(oauthApplicationID ?? "none"), "
            + "apiAccess: \(apiAccess.rawValue), "
            + "credential: \(credential))"
    }

    var debugDescription: String {
        description
    }

    init(
        host: GitLabHost,
        user: GitLabUserSummary,
        oauthApplicationID: String?,
        personalAccessTokenMetadata: GitLabPersonalAccessTokenMetadata?,
        credential: GitLabCredential
    ) throws(GitLabStoredSessionError) {
        let normalizedApplicationID = oauthApplicationID?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch credential.kind {
        case .oauth:
            guard let normalizedApplicationID, !normalizedApplicationID.isEmpty else {
                throw .missingOAuthApplicationID
            }
            guard personalAccessTokenMetadata == nil else {
                throw .unexpectedPersonalAccessTokenMetadata
            }
            self.oauthApplicationID = normalizedApplicationID
        case .personalAccessToken:
            guard normalizedApplicationID == nil else {
                throw .unexpectedOAuthApplicationID
            }
            guard let personalAccessTokenMetadata else {
                throw .missingPersonalAccessTokenMetadata
            }
            guard personalAccessTokenMetadata.supportsGlabAPI else {
                throw .insufficientPersonalAccessTokenScope
            }
            self.oauthApplicationID = nil
        }

        self.host = host
        self.user = user
        self.personalAccessTokenMetadata = personalAccessTokenMetadata
        self.credential = credential
    }

    func replacingOAuthCredential(
        _ credential: GitLabCredential
    ) throws(GitLabStoredSessionError) -> Self {
        try Self(
            host: host,
            user: user,
            oauthApplicationID: oauthApplicationID,
            personalAccessTokenMetadata: personalAccessTokenMetadata,
            credential: credential
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let host = try container.decode(GitLabHost.self, forKey: .host)
        let user = try container.decode(GitLabUserSummary.self, forKey: .user)
        let oauthApplicationID = try container.decodeIfPresent(
            String.self,
            forKey: .oauthApplicationID
        )
        let personalAccessTokenMetadata = try container.decodeIfPresent(
            GitLabPersonalAccessTokenMetadata.self,
            forKey: .personalAccessTokenMetadata
        )
        let credential = try container.decode(
            GitLabCredential.self,
            forKey: .credential
        )

        do {
            try self.init(
                host: host,
                user: user,
                oauthApplicationID: oauthApplicationID,
                personalAccessTokenMetadata: personalAccessTokenMetadata,
                credential: credential
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .credential,
                in: container,
                debugDescription: error.description
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(user, forKey: .user)
        try container.encodeIfPresent(
            oauthApplicationID,
            forKey: .oauthApplicationID
        )
        try container.encodeIfPresent(
            personalAccessTokenMetadata,
            forKey: .personalAccessTokenMetadata
        )
        try container.encode(credential, forKey: .credential)
    }
}
