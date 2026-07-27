import Foundation

nonisolated enum GitLabCredentialKind: String, Codable, Sendable {
    case oauth
    case personalAccessToken
}

nonisolated enum GitLabCredentialError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyAccessToken
    case emptyRefreshToken

    var description: String {
        switch self {
        case .emptyAccessToken:
            "A GitLab access token cannot be empty."
        case .emptyRefreshToken:
            "A GitLab OAuth refresh token cannot be empty."
        }
    }
}

nonisolated struct GitLabCredential:
    Codable,
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    private enum Storage: Equatable, Sendable {
        case oauth(accessToken: String, refreshToken: String?, expiresAt: Date?)
        case personalAccessToken(String)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case accessToken
        case refreshToken
        case expiresAt
    }

    private let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    var kind: GitLabCredentialKind {
        switch storage {
        case .oauth:
            .oauth
        case .personalAccessToken:
            .personalAccessToken
        }
    }

    var oauthExpiresAt: Date? {
        switch storage {
        case let .oauth(_, _, expiresAt):
            expiresAt
        case .personalAccessToken:
            nil
        }
    }

    var canRefreshOAuth: Bool {
        switch storage {
        case let .oauth(_, refreshToken, _):
            refreshToken != nil
        case .personalAccessToken:
            false
        }
    }

    var authorization: GitLabAuthorization {
        switch storage {
        case let .oauth(accessToken, _, _):
            .oauth(accessToken: accessToken)
        case let .personalAccessToken(token):
            .personalAccessToken(token)
        }
    }

    var description: String {
        switch storage {
        case let .oauth(_, refreshToken, expiresAt):
            let refreshDescription = refreshToken == nil ? "none" : "<redacted>"
            return "OAuth credential(access: <redacted>, refresh: \(refreshDescription), "
                + "expiresAt: \(String(describing: expiresAt)))"
        case .personalAccessToken:
            return "Personal access token credential(token: <redacted>)"
        }
    }

    var debugDescription: String {
        description
    }

    static func oauth(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date?
    ) throws(GitLabCredentialError) -> Self {
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .emptyAccessToken
        }
        if let refreshToken {
            guard !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw .emptyRefreshToken
            }
        }

        return Self(
            storage: .oauth(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt
            )
        )
    }

    static func personalAccessToken(
        _ token: String
    ) throws(GitLabCredentialError) -> Self {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .emptyAccessToken
        }

        return Self(storage: .personalAccessToken(token))
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(GitLabCredentialKind.self, forKey: .kind)
        let accessToken = try container.decode(String.self, forKey: .accessToken)

        switch kind {
        case .oauth:
            let refreshToken = try container.decodeIfPresent(
                String.self,
                forKey: .refreshToken
            )
            let expiresAt = try container.decodeIfPresent(
                Date.self,
                forKey: .expiresAt
            )

            do {
                self = try Self.oauth(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresAt: expiresAt
                )
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .accessToken,
                    in: container,
                    debugDescription: error.description
                )
            }
        case .personalAccessToken:
            do {
                self = try Self.personalAccessToken(accessToken)
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .accessToken,
                    in: container,
                    debugDescription: error.description
                )
            }
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch storage {
        case let .oauth(accessToken, refreshToken, expiresAt):
            try container.encode(accessToken, forKey: .accessToken)
            try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
            try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        case let .personalAccessToken(token):
            try container.encode(token, forKey: .accessToken)
        }
    }
}
