import Foundation

nonisolated enum GitLabOAuthConfigurationError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case invalidHost(GitLabHostError)
    case missingApplicationID
    case invalidRedirectURI
    case invalidURL

    var description: String {
        switch self {
        case let .invalidHost(error):
            error.description
        case .missingApplicationID:
            "Enter the GitLab OAuth Application ID."
        case .invalidRedirectURI:
            "The Glab OAuth redirect URI is invalid."
        case .invalidURL:
            "Glab could not build the GitLab OAuth URL."
        }
    }
}

nonisolated enum GitLabOAuthCallbackError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case invalidCallback
    case stateMismatch
    case accessDenied
    case invalidApplication
    case applicationUnavailable
    case invalidRedirectURI
    case authorizationFailed

    var description: String {
        switch self {
        case .invalidCallback:
            "GitLab returned an invalid OAuth callback."
        case .stateMismatch:
            "Glab rejected the OAuth callback because its security state did not match."
        case .accessDenied:
            "GitLab sign-in was denied."
        case .invalidApplication:
            "GitLab does not recognize this OAuth Application ID."
        case .applicationUnavailable:
            "This GitLab instance does not allow this OAuth application."
        case .invalidRedirectURI:
            "The OAuth application's redirect URI must be glab://oauth/callback."
        case .authorizationFailed:
            "GitLab could not authorize Glab."
        }
    }
}

nonisolated struct GitLabOAuthConfiguration: Equatable, Sendable {
    static let callbackScheme = "glab"
    static let redirectURIString = "glab://oauth/callback"

    let host: GitLabHost
    let applicationID: String
    let redirectURI: URL

    init(
        instanceURL: String,
        applicationID: String,
        redirectURI: URL? = URL(string: Self.redirectURIString)
    ) throws(GitLabOAuthConfigurationError) {
        do {
            host = try GitLabHost(instanceURL)
        } catch {
            throw .invalidHost(error)
        }

        let normalizedApplicationID = applicationID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedApplicationID.isEmpty else {
            throw .missingApplicationID
        }
        guard
            let redirectURI,
            redirectURI.scheme == Self.callbackScheme,
            redirectURI.host(percentEncoded: false) == "oauth",
            redirectURI.path == "/callback"
        else {
            throw .invalidRedirectURI
        }

        self.applicationID = normalizedApplicationID
        self.redirectURI = redirectURI
    }

    func authorizationURL(
        pkce: GitLabOAuthPKCE
    ) throws(GitLabOAuthConfigurationError) -> URL {
        var components = try oauthComponents(path: ["oauth", "authorize"])
        components.queryItems = [
            URLQueryItem(name: "client_id", value: applicationID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "scope", value: "api"),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let url = components.url else {
            throw .invalidURL
        }
        return url
    }

    func authorizationCodeTokenRequest(
        code: String,
        codeVerifier: String
    ) throws(GitLabOAuthConfigurationError) -> URLRequest {
        try tokenRequest(
            queryItems: [
                URLQueryItem(name: "client_id", value: applicationID),
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "grant_type", value: "authorization_code"),
                URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
                URLQueryItem(name: "code_verifier", value: codeVerifier),
            ]
        )
    }

    func refreshTokenRequest(
        refreshToken: String
    ) throws(GitLabOAuthConfigurationError) -> URLRequest {
        try tokenRequest(
            queryItems: [
                URLQueryItem(name: "client_id", value: applicationID),
                URLQueryItem(name: "refresh_token", value: refreshToken),
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            ]
        )
    }

    func authorizationCode(
        from callbackURL: URL,
        expectedState: String
    ) throws(GitLabOAuthCallbackError) -> String {
        guard
            callbackURL.scheme == redirectURI.scheme,
            callbackURL.host(percentEncoded: false)
                == redirectURI.host(percentEncoded: false),
            callbackURL.path == redirectURI.path,
            let components = URLComponents(
                url: callbackURL,
                resolvingAgainstBaseURL: false
            )
        else {
            throw .invalidCallback
        }

        let values = Dictionary(
            components.queryItems?.compactMap { item in
                item.value.map { (item.name, $0) }
            } ?? [],
            uniquingKeysWith: { first, _ in first }
        )

        guard values["state"] == expectedState else {
            throw .stateMismatch
        }

        if let error = values["error"] {
            throw Self.callbackError(for: error)
        }

        guard
            let code = values["code"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !code.isEmpty
        else {
            throw .invalidCallback
        }
        return code
    }

    var applicationSetupURL: URL? {
        var components = URLComponents(
            url: host.siteURL,
            resolvingAgainstBaseURL: false
        )
        components?.percentEncodedPath += "/-/user_settings/applications"
        return components?.url
    }

    private func tokenRequest(
        queryItems: [URLQueryItem]
    ) throws(GitLabOAuthConfigurationError) -> URLRequest {
        let tokenURLComponents = try oauthComponents(path: ["oauth", "token"])
        guard let url = tokenURLComponents.url else {
            throw .invalidURL
        }

        var formComponents = URLComponents()
        formComponents.queryItems = queryItems
        guard let encodedForm = formComponents.percentEncodedQuery else {
            throw .invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(encodedForm.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        return request
    }

    private func oauthComponents(
        path: [String]
    ) throws(GitLabOAuthConfigurationError) -> URLComponents {
        guard var components = URLComponents(
            url: host.siteURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw .invalidURL
        }

        for component in path {
            components.percentEncodedPath += "/\(component)"
        }
        return components
    }

    private static func callbackError(
        for code: String
    ) -> GitLabOAuthCallbackError {
        switch code {
        case "access_denied":
            .accessDenied
        case "invalid_client":
            .invalidApplication
        case "unauthorized_client":
            .applicationUnavailable
        case "invalid_redirect_uri":
            .invalidRedirectURI
        default:
            .authorizationFailed
        }
    }
}

