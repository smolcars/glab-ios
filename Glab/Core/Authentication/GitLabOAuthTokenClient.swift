import Foundation

nonisolated enum GitLabOAuthTokenError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case configuration(GitLabOAuthConfigurationError)
    case invalidApplication
    case invalidGrant
    case applicationUnavailable
    case invalidRequest
    case unsupportedResponse
    case connectivity(URLError.Code)
    case cancelled
    case server(statusCode: Int)
    case http(statusCode: Int)
    case transport

    var description: String {
        switch self {
        case let .configuration(error):
            error.description
        case .invalidApplication:
            "GitLab does not recognize this OAuth Application ID."
        case .invalidGrant:
            "GitLab rejected the OAuth code or refresh token. Start sign-in again and verify the redirect URI."
        case .applicationUnavailable:
            "This GitLab instance does not allow this OAuth application. Ask an administrator to register Glab or use an access token."
        case .invalidRequest:
            "GitLab rejected the OAuth setup. Verify that the application is public and uses glab://oauth/callback."
        case .unsupportedResponse:
            "GitLab returned an OAuth token response that Glab could not read."
        case let .connectivity(code):
            GitLabAPIError.connectivity(code).description
        case .cancelled:
            "GitLab sign-in was cancelled."
        case let .server(statusCode):
            "GitLab's OAuth service is temporarily unavailable (HTTP \(statusCode))."
        case let .http(statusCode):
            "GitLab returned an unexpected OAuth response (HTTP \(statusCode))."
        case .transport:
            "The GitLab OAuth request could not be completed."
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }
}

nonisolated protocol GitLabOAuthTokenExchanging: Sendable {
    func exchangeAuthorizationCode(
        configuration: GitLabOAuthConfiguration,
        code: String,
        codeVerifier: String
    ) async throws(GitLabOAuthTokenError) -> GitLabCredential

    func refresh(
        configuration: GitLabOAuthConfiguration,
        refreshToken: String
    ) async throws(GitLabOAuthTokenError) -> GitLabCredential
}

nonisolated struct GitLabOAuthTokenClient<Transport>:
    GitLabOAuthTokenExchanging,
    Sendable
where Transport: GitLabHTTPTransport {
    private let transport: Transport

    init(transport: Transport) {
        self.transport = transport
    }

    @concurrent
    func exchangeAuthorizationCode(
        configuration: GitLabOAuthConfiguration,
        code: String,
        codeVerifier: String
    ) async throws(GitLabOAuthTokenError) -> GitLabCredential {
        let request: URLRequest

        do {
            request = try configuration.authorizationCodeTokenRequest(
                code: code,
                codeVerifier: codeVerifier
            )
        } catch {
            throw .configuration(error)
        }

        return try await credential(for: request)
    }

    @concurrent
    func refresh(
        configuration: GitLabOAuthConfiguration,
        refreshToken: String
    ) async throws(GitLabOAuthTokenError) -> GitLabCredential {
        let request: URLRequest

        do {
            request = try configuration.refreshTokenRequest(
                refreshToken: refreshToken
            )
        } catch {
            throw .configuration(error)
        }

        return try await credential(for: request)
    }

    private func credential(
        for request: URLRequest
    ) async throws(GitLabOAuthTokenError) -> GitLabCredential {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await transport.data(for: request)
        } catch is CancellationError {
            throw .cancelled
        } catch let error as URLError {
            if error.code == .cancelled {
                throw .cancelled
            }
            throw .connectivity(error.code)
        } catch {
            throw .transport
        }

        guard !Task.isCancelled else {
            throw .cancelled
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw .unsupportedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.endpointError(
                statusCode: httpResponse.statusCode,
                data: data
            )
        }

        let responseBody: GitLabOAuthTokenResponse

        do {
            responseBody = try JSONDecoder().decode(
                GitLabOAuthTokenResponse.self,
                from: data
            )
        } catch {
            throw .unsupportedResponse
        }

        guard
            responseBody.tokenType.caseInsensitiveCompare("bearer") == .orderedSame,
            responseBody.expiresIn > 0,
            !responseBody.refreshToken
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        else {
            throw .unsupportedResponse
        }

        let (expirationTimestamp, didOverflow) = responseBody.createdAt
            .addingReportingOverflow(responseBody.expiresIn)
        guard responseBody.createdAt >= 0, !didOverflow else {
            throw .unsupportedResponse
        }

        do {
            return try GitLabCredential.oauth(
                accessToken: responseBody.accessToken,
                refreshToken: responseBody.refreshToken,
                expiresAt: Date(
                    timeIntervalSince1970:
                        TimeInterval(expirationTimestamp)
                )
            )
        } catch {
            throw .unsupportedResponse
        }
    }

    private static func endpointError(
        statusCode: Int,
        data: Data
    ) -> GitLabOAuthTokenError {
        if
            let oauthError = try? JSONDecoder().decode(
                GitLabOAuthEndpointError.self,
                from: data
            )
        {
            switch oauthError.error {
            case "invalid_client":
                return .invalidApplication
            case "invalid_grant":
                return .invalidGrant
            case "unauthorized_client":
                return .applicationUnavailable
            case "invalid_request", "unsupported_grant_type":
                return .invalidRequest
            default:
                break
            }
        }

        switch statusCode {
        case 500...599:
            return .server(statusCode: statusCode)
        default:
            return .http(statusCode: statusCode)
        }
    }
}

private nonisolated struct GitLabOAuthTokenResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let createdAt: Int

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case createdAt = "created_at"
    }
}

private nonisolated struct GitLabOAuthEndpointError: Decodable, Sendable {
    let error: String
}
