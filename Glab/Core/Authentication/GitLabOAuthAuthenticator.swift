import Foundation

nonisolated enum GitLabOAuthSignInError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case configuration(GitLabOAuthConfigurationError)
    case pkce(GitLabOAuthPKCEError)
    case web(GitLabOAuthWebAuthenticationError)
    case callback(GitLabOAuthCallbackError)
    case token(GitLabOAuthTokenError)
    case invalidToken
    case forbidden
    case unsupportedResponse
    case api(GitLabAPIError)

    var description: String {
        switch self {
        case let .configuration(error):
            error.description
        case let .pkce(error):
            error.description
        case let .web(error):
            error.description
        case let .callback(error):
            error.description
        case let .token(error):
            error.description
        case .invalidToken:
            "GitLab rejected the new OAuth token. Start sign-in again."
        case .forbidden:
            "The OAuth token cannot read your GitLab account."
        case .unsupportedResponse:
            "GitLab returned an authentication response that Glab could not read."
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

@MainActor
protocol GitLabOAuthAuthenticating: Sendable {
    func authenticate(
        configuration: GitLabOAuthConfiguration
    ) async throws(GitLabOAuthSignInError) -> GitLabStoredSession
}

@MainActor
struct GitLabOAuthAuthenticator<RandomBytesProvider, TokenExchanger, Transport, WebAuthenticator>:
    GitLabOAuthAuthenticating
where
    RandomBytesProvider: GitLabOAuthRandomBytesProviding,
    TokenExchanger: GitLabOAuthTokenExchanging,
    Transport: GitLabHTTPTransport,
    WebAuthenticator: GitLabOAuthWebAuthenticating
{
    private let pkceGenerator: GitLabOAuthPKCEGenerator<RandomBytesProvider>
    private let tokenExchanger: TokenExchanger
    private let transport: Transport
    private let webAuthenticator: WebAuthenticator

    init(
        pkceGenerator: GitLabOAuthPKCEGenerator<RandomBytesProvider>,
        tokenExchanger: TokenExchanger,
        transport: Transport,
        webAuthenticator: WebAuthenticator
    ) {
        self.pkceGenerator = pkceGenerator
        self.tokenExchanger = tokenExchanger
        self.transport = transport
        self.webAuthenticator = webAuthenticator
    }

    func authenticate(
        configuration: GitLabOAuthConfiguration
    ) async throws(GitLabOAuthSignInError) -> GitLabStoredSession {
        let pkce: GitLabOAuthPKCE

        do {
            pkce = try pkceGenerator.generate()
        } catch {
            throw .pkce(error)
        }

        let authorizationURL: URL

        do {
            authorizationURL = try configuration.authorizationURL(pkce: pkce)
        } catch {
            throw .configuration(error)
        }

        let callbackURL: URL

        do {
            callbackURL = try await webAuthenticator.authenticate(
                at: authorizationURL,
                callbackURLScheme: GitLabOAuthConfiguration.callbackScheme
            )
        } catch {
            throw .web(error)
        }

        let authorizationCode: String

        do {
            authorizationCode = try configuration.authorizationCode(
                from: callbackURL,
                expectedState: pkce.state
            )
        } catch {
            throw .callback(error)
        }

        let credential: GitLabCredential

        do {
            credential = try await tokenExchanger.exchangeAuthorizationCode(
                configuration: configuration,
                code: authorizationCode,
                codeVerifier: pkce.codeVerifier
            )
        } catch {
            throw .token(error)
        }

        let client = GitLabClient(
            requestBuilder: GitLabRequestBuilder(
                host: configuration.host,
                authorization: credential.authorization
            ),
            transport: transport
        )
        let user: GitLabAuthenticatedUser

        do {
            user = try await client.send(
                GitLabAPIRequest<GitLabAuthenticatedUser>.get(path: ["user"])
            )
        } catch {
            throw Self.mapAPIError(error)
        }

        do {
            return try GitLabStoredSession(
                host: configuration.host,
                user: GitLabUserSummary(
                    id: user.id,
                    username: user.username,
                    name: user.name,
                    avatarURL: user.avatarURL
                ),
                oauthApplicationID: configuration.applicationID,
                personalAccessTokenMetadata: nil,
                credential: credential
            )
        } catch {
            throw .unsupportedResponse
        }
    }

    private static func mapAPIError(
        _ error: GitLabAPIError
    ) -> GitLabOAuthSignInError {
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
