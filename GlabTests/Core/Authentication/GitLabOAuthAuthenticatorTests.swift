import Foundation
import Testing
@testable import Glab

@Suite("GitLab OAuth authentication")
@MainActor
struct GitLabOAuthAuthenticatorTests {
    @Test("Completes PKCE, exchanges the code, validates the user, and creates a session")
    func authenticates() async throws {
        let token = try GitLabCredential.oauth(
            accessToken: "oauth-access",
            refreshToken: "oauth-refresh",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let webAuthenticator = StubWebAuthenticator(outcome: .code("code-123"))
        let tokenExchanger = StubTokenExchanger(outcome: .success(token))
        let authenticator = makeAuthenticator(
            webAuthenticator: webAuthenticator,
            tokenExchanger: tokenExchanger,
            apiOutcome: .user
        )
        let configuration = try GitLabOAuthConfiguration(
            instanceURL: "https://gitlab.example.com/company",
            applicationID: "instance-application-id"
        )

        let session = try await authenticator.authenticate(
            configuration: configuration
        )

        #expect(session.host == configuration.host)
        #expect(session.user.username == "octocat")
        #expect(session.oauthApplicationID == "instance-application-id")
        #expect(session.credential == token)
        #expect(session.credentialKind == .oauth)

        let authorizationURL = try #require(webAuthenticator.authorizationURL)
        #expect(
            authorizationURL.absoluteString.hasPrefix(
                "https://gitlab.example.com/company/oauth/authorize?"
            )
        )
        #expect(webAuthenticator.callbackURLScheme == "glab")

        let exchange = try #require(await tokenExchanger.lastExchange)
        #expect(exchange.configuration == configuration)
        #expect(exchange.code == "code-123")
        #expect((43...128).contains(exchange.codeVerifier.count))
    }

    @Test("Rejects denied and state-mismatched callbacks before token exchange")
    func rejectsCallbackFailures() async throws {
        let token = try GitLabCredential.oauth(
            accessToken: "unused",
            refreshToken: "unused",
            expiresAt: nil
        )
        let deniedExchanger = StubTokenExchanger(outcome: .success(token))
        let denied = makeAuthenticator(
            webAuthenticator: StubWebAuthenticator(outcome: .denied),
            tokenExchanger: deniedExchanger,
            apiOutcome: .user
        )
        let mismatchExchanger = StubTokenExchanger(outcome: .success(token))
        let mismatch = makeAuthenticator(
            webAuthenticator: StubWebAuthenticator(outcome: .stateMismatch),
            tokenExchanger: mismatchExchanger,
            apiOutcome: .user
        )
        let configuration = try makeConfiguration()

        await #expect(
            throws: GitLabOAuthSignInError.callback(.accessDenied)
        ) {
            try await denied.authenticate(configuration: configuration)
        }
        await #expect(
            throws: GitLabOAuthSignInError.callback(.stateMismatch)
        ) {
            try await mismatch.authenticate(configuration: configuration)
        }
        #expect(await deniedExchanger.exchangeCount == 0)
        #expect(await mismatchExchanger.exchangeCount == 0)
    }

    @Test("Maps user cancellation and OAuth application setup failures")
    func mapsWebAndSetupFailures() async throws {
        let token = try GitLabCredential.oauth(
            accessToken: "unused",
            refreshToken: "unused",
            expiresAt: nil
        )
        let cancelled = makeAuthenticator(
            webAuthenticator: StubWebAuthenticator(outcome: .cancelled),
            tokenExchanger: StubTokenExchanger(outcome: .success(token)),
            apiOutcome: .user
        )
        let invalidApplication = makeAuthenticator(
            webAuthenticator: StubWebAuthenticator(outcome: .code("code")),
            tokenExchanger: StubTokenExchanger(
                outcome: .failure(.invalidApplication)
            ),
            apiOutcome: .user
        )
        let configuration = try makeConfiguration()

        await #expect(
            throws: GitLabOAuthSignInError.web(.cancelled)
        ) {
            try await cancelled.authenticate(configuration: configuration)
        }
        await #expect(
            throws: GitLabOAuthSignInError.token(.invalidApplication)
        ) {
            try await invalidApplication.authenticate(
                configuration: configuration
            )
        }
    }

    @Test("Rejects an OAuth token that cannot validate the current user")
    func rejectsInvalidUserToken() async throws {
        let token = try GitLabCredential.oauth(
            accessToken: "invalid",
            refreshToken: "refresh",
            expiresAt: nil
        )
        let authenticator = makeAuthenticator(
            webAuthenticator: StubWebAuthenticator(outcome: .code("code")),
            tokenExchanger: StubTokenExchanger(outcome: .success(token)),
            apiOutcome: .unauthenticated
        )

        await #expect(throws: GitLabOAuthSignInError.invalidToken) {
            try await authenticator.authenticate(
                configuration: makeConfiguration()
            )
        }
    }
}

private extension GitLabOAuthAuthenticatorTests {
    @MainActor
    final class StubWebAuthenticator: GitLabOAuthWebAuthenticating {
        enum Outcome {
            case code(String)
            case denied
            case stateMismatch
            case cancelled
        }

        let outcome: Outcome
        private(set) var authorizationURL: URL?
        private(set) var callbackURLScheme: String?

        init(outcome: Outcome) {
            self.outcome = outcome
        }

        func authenticate(
            at authorizationURL: URL,
            callbackURLScheme: String
        ) async throws(GitLabOAuthWebAuthenticationError) -> URL {
            self.authorizationURL = authorizationURL
            self.callbackURLScheme = callbackURLScheme

            if case .cancelled = outcome {
                throw .cancelled
            }

            let components = URLComponents(
                url: authorizationURL,
                resolvingAgainstBaseURL: false
            )
            let state = components?.queryItems?
                .first(where: { $0.name == "state" })?
                .value ?? ""

            switch outcome {
            case let .code(code):
                return URL(
                    string: "glab://oauth/callback?code=\(code)&state=\(state)"
                )!
            case .denied:
                return URL(
                    string: "glab://oauth/callback?error=access_denied&state=\(state)"
                )!
            case .stateMismatch:
                return URL(
                    string: "glab://oauth/callback?code=code&state=wrong"
                )!
            case .cancelled:
                throw .cancelled
            }
        }
    }

    actor StubTokenExchanger: GitLabOAuthTokenExchanging {
        struct Exchange: Sendable {
            let configuration: GitLabOAuthConfiguration
            let code: String
            let codeVerifier: String
        }

        enum Outcome: Sendable {
            case success(GitLabCredential)
            case failure(GitLabOAuthTokenError)
        }

        let outcome: Outcome
        private(set) var exchanges: [Exchange] = []

        var lastExchange: Exchange? {
            exchanges.last
        }

        var exchangeCount: Int {
            exchanges.count
        }

        init(outcome: Outcome) {
            self.outcome = outcome
        }

        func exchangeAuthorizationCode(
            configuration: GitLabOAuthConfiguration,
            code: String,
            codeVerifier: String
        ) async throws(GitLabOAuthTokenError) -> GitLabCredential {
            exchanges.append(
                Exchange(
                    configuration: configuration,
                    code: code,
                    codeVerifier: codeVerifier
                )
            )

            switch outcome {
            case let .success(credential):
                return credential
            case let .failure(error):
                throw error
            }
        }

        func refresh(
            configuration: GitLabOAuthConfiguration,
            refreshToken: String
        ) async throws(GitLabOAuthTokenError) -> GitLabCredential {
            throw .invalidGrant
        }
    }

    nonisolated struct FixedRandomBytesProvider:
        GitLabOAuthRandomBytesProviding,
        Sendable
    {
        func randomBytes(
            count: Int
        ) throws(GitLabOAuthPKCEError) -> Data {
            Data((0..<count).map { UInt8($0 % 256) })
        }
    }

    nonisolated enum APIOutcome: Sendable {
        case user
        case unauthenticated
    }

    nonisolated struct StubAPITransport: GitLabHTTPTransport {
        let outcome: APIOutcome

        func data(
            for request: URLRequest
        ) async throws -> (Data, URLResponse) {
            let statusCode: Int
            let data: Data

            switch outcome {
            case .user:
                statusCode = 200
                data = Data(
                    """
                    {
                      "id": 42,
                      "username": "octocat",
                      "name": "The Octocat",
                      "avatar_url": "https://gitlab.example.com/avatar.png"
                    }
                    """.utf8
                )
            case .unauthenticated:
                statusCode = 401
                data = Data()
            }

            return (
                data,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: "HTTP/2",
                    headerFields: nil
                )!
            )
        }
    }

    func makeAuthenticator(
        webAuthenticator: StubWebAuthenticator,
        tokenExchanger: StubTokenExchanger,
        apiOutcome: APIOutcome
    ) -> GitLabOAuthAuthenticator<
        FixedRandomBytesProvider,
        StubTokenExchanger,
        StubAPITransport,
        StubWebAuthenticator
    > {
        GitLabOAuthAuthenticator(
            pkceGenerator: GitLabOAuthPKCEGenerator(
                randomBytesProvider: FixedRandomBytesProvider()
            ),
            tokenExchanger: tokenExchanger,
            transport: StubAPITransport(outcome: apiOutcome),
            webAuthenticator: webAuthenticator
        )
    }

    nonisolated func makeConfiguration() throws -> GitLabOAuthConfiguration {
        try GitLabOAuthConfiguration(
            instanceURL: "gitlab.com",
            applicationID: "application-id"
        )
    }
}
