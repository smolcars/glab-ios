import Foundation

nonisolated enum PersonalAccessTokenSignInError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case invalidHost(GitLabHostError)
    case emptyToken
    case invalidToken
    case forbidden
    case insufficientScope
    case unsupportedTokenInspection
    case unsupportedResponse
    case api(GitLabAPIError)

    var description: String {
        switch self {
        case let .invalidHost(error):
            error.description
        case .emptyToken:
            "Paste a GitLab personal access token to continue."
        case .invalidToken:
            "GitLab rejected this access token. Check that it has not expired or been revoked."
        case .forbidden:
            "This access token cannot read your GitLab account."
        case .insufficientScope:
            "Create a personal access token with the api or read_api scope."
        case .unsupportedTokenInspection:
            "This GitLab server cannot inspect the personal access token. Update GitLab or use OAuth when available."
        case .unsupportedResponse:
            "This GitLab server returned an authentication response that Glab could not read."
        case let .api(error):
            error.description
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }
}

nonisolated protocol PersonalAccessTokenAuthenticating: Sendable {
    func authenticate(
        instanceURL: String,
        token: String
    ) async throws(PersonalAccessTokenSignInError) -> GitLabStoredSession
}

nonisolated struct GitLabPersonalAccessTokenAuthenticator<Transport>:
    PersonalAccessTokenAuthenticating,
    Sendable
where Transport: GitLabHTTPTransport {
    private let transport: Transport

    init(transport: Transport) {
        self.transport = transport
    }

    @concurrent
    func authenticate(
        instanceURL: String,
        token: String
    ) async throws(PersonalAccessTokenSignInError) -> GitLabStoredSession {
        let host: GitLabHost

        do {
            host = try GitLabHost(instanceURL)
        } catch {
            throw .invalidHost(error)
        }

        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw .emptyToken
        }

        let credential: GitLabCredential

        do {
            credential = try GitLabCredential.personalAccessToken(normalizedToken)
        } catch {
            throw .emptyToken
        }

        let client = GitLabClient(
            requestBuilder: GitLabRequestBuilder(
                host: host,
                authorization: credential.authorization
            ),
            transport: transport
        )

        let authenticatedUser: GitLabAuthenticatedUser

        do {
            authenticatedUser = try await client.send(
                GitLabAPIRequest<GitLabAuthenticatedUser>.get(
                    requires: .read,
                    path: ["user"]
                )
            )
        } catch {
            throw Self.mapAPIError(error)
        }

        let tokenDetails: GitLabPersonalAccessTokenDetails

        do {
            tokenDetails = try await client.send(
                GitLabAPIRequest<GitLabPersonalAccessTokenDetails>.get(
                    requires: .read,
                    path: ["personal_access_tokens", "self"]
                )
            )
        } catch .notFound {
            throw .unsupportedTokenInspection
        } catch .http(statusCode: 405) {
            throw .unsupportedTokenInspection
        } catch {
            throw Self.mapAPIError(error)
        }

        guard
            tokenDetails.active,
            !tokenDetails.revoked,
            tokenDetails.userID == authenticatedUser.id
        else {
            throw .invalidToken
        }

        let tokenMetadata = GitLabPersonalAccessTokenMetadata(
            scopes: tokenDetails.scopes,
            expiresOn: tokenDetails.expiresOn
        )
        guard tokenMetadata.supportsGlabAPI else {
            throw .insufficientScope
        }

        do {
            return try GitLabStoredSession(
                host: host,
                user: GitLabUserSummary(
                    id: authenticatedUser.id,
                    username: authenticatedUser.username,
                    name: authenticatedUser.name,
                    avatarURL: authenticatedUser.avatarURL
                ),
                oauthApplicationID: nil,
                personalAccessTokenMetadata: tokenMetadata,
                credential: credential
            )
        } catch {
            throw .unsupportedResponse
        }
    }

    private static func mapAPIError(
        _ error: GitLabAPIError
    ) -> PersonalAccessTokenSignInError {
        switch error {
        case .unauthenticated:
            .invalidToken
        case .forbidden:
            .forbidden
        case .decoding, .invalidResponse:
            .unsupportedResponse
        default:
            .api(error)
        }
    }
}

private nonisolated struct GitLabPersonalAccessTokenDetails: Decodable, Sendable {
    let revoked: Bool
    let scopes: [String]
    let userID: Int
    let active: Bool
    let expiresOn: String?

    private enum CodingKeys: String, CodingKey {
        case revoked
        case scopes
        case userID = "user_id"
        case active
        case expiresOn = "expires_at"
    }
}
