import Foundation

nonisolated struct GitLabUserSummary: Codable, Equatable, Sendable {
    let id: Int
    let username: String
    let name: String
    let avatarURL: URL?
}

nonisolated enum GitLabStoredSessionError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case missingOAuthApplicationID
    case unexpectedOAuthApplicationID

    var description: String {
        switch self {
        case .missingOAuthApplicationID:
            "An OAuth session requires the GitLab host's application ID."
        case .unexpectedOAuthApplicationID:
            "A personal access token session cannot include an OAuth application ID."
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
        case credential
    }

    let host: GitLabHost
    let user: GitLabUserSummary
    let oauthApplicationID: String?
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

    var description: String {
        "GitLabStoredSession(host: \(host.siteURL.absoluteString), "
            + "username: \(user.username), "
            + "oauthApplicationID: \(oauthApplicationID ?? "none"), "
            + "credential: \(credential))"
    }

    var debugDescription: String {
        description
    }

    init(
        host: GitLabHost,
        user: GitLabUserSummary,
        oauthApplicationID: String?,
        credential: GitLabCredential
    ) throws(GitLabStoredSessionError) {
        let normalizedApplicationID = oauthApplicationID?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch credential.kind {
        case .oauth:
            guard let normalizedApplicationID, !normalizedApplicationID.isEmpty else {
                throw .missingOAuthApplicationID
            }
            self.oauthApplicationID = normalizedApplicationID
        case .personalAccessToken:
            guard normalizedApplicationID == nil else {
                throw .unexpectedOAuthApplicationID
            }
            self.oauthApplicationID = nil
        }

        self.host = host
        self.user = user
        self.credential = credential
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let host = try container.decode(GitLabHost.self, forKey: .host)
        let user = try container.decode(GitLabUserSummary.self, forKey: .user)
        let oauthApplicationID = try container.decodeIfPresent(
            String.self,
            forKey: .oauthApplicationID
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
        try container.encode(credential, forKey: .credential)
    }
}
