import Foundation
import Testing
@testable import Glab

@Suite("GitLab OAuth flow construction")
struct GitLabOAuthFlowConstructionTests {
    @Test("Matches GitLab's documented PKCE challenge vector")
    func matchesPKCEVector() {
        let verifier = "ks02i3jdikdo2k0dkfodf3m39rjfjsdk0wk349rj3jrhf"

        #expect(
            GitLabOAuthPKCE.challenge(for: verifier)
                == "2i0WFA-0AerkjQm4X4oDEhqA17QIAKNjXpagHBXmO_U"
        )
    }

    @Test("Generates valid unpredictable OAuth values from secure bytes")
    func generatesOAuthValues() throws {
        let bytes = Data((0..<96).map(UInt8.init))
        let generator = GitLabOAuthPKCEGenerator(
            randomBytesProvider: StubRandomBytesProvider(data: bytes)
        )

        let pkce = try generator.generate()

        #expect(pkce.state.count == 43)
        #expect(pkce.codeVerifier.count == 86)
        #expect(pkce.codeChallenge.count == 43)
        #expect(!pkce.state.contains("="))
        #expect(!pkce.codeVerifier.contains("="))
    }

    @Test("Rejects malformed PKCE values and random data")
    func rejectsMalformedPKCEValues() {
        #expect(throws: GitLabOAuthPKCEError.invalidState) {
            try GitLabOAuthPKCE(
                state: "",
                codeVerifier: String(repeating: "a", count: 43)
            )
        }
        #expect(throws: GitLabOAuthPKCEError.invalidCodeVerifier) {
            try GitLabOAuthPKCE(
                state: "state",
                codeVerifier: "short"
            )
        }
        #expect(throws: GitLabOAuthPKCEError.invalidRandomData) {
            try GitLabOAuthPKCEGenerator(
                randomBytesProvider: StubRandomBytesProvider(
                    data: Data(repeating: 1, count: 95)
                )
            )
            .generate()
        }
    }

    @Test("Builds GitLab.com authorization and token requests without a secret")
    func buildsGitLabDotComRequests() throws {
        let configuration = try GitLabOAuthConfiguration(
            instanceURL: "gitlab.com",
            applicationID: "  public-app-id  "
        )
        let pkce = try GitLabOAuthPKCE(
            state: "secure_state",
            codeVerifier: String(repeating: "v", count: 64)
        )

        let authorizationURL = try configuration.authorizationURL(pkce: pkce)
        let authorizationComponents = try #require(
            URLComponents(
                url: authorizationURL,
                resolvingAgainstBaseURL: false
            )
        )
        let authorizationQuery = queryDictionary(authorizationComponents.queryItems)

        #expect(
            authorizationComponents.string?.hasPrefix(
                "https://gitlab.com/oauth/authorize?"
            ) == true
        )
        #expect(configuration.applicationID == "public-app-id")
        #expect(authorizationQuery["client_id"] == "public-app-id")
        #expect(authorizationQuery["redirect_uri"] == "glab://oauth/callback")
        #expect(authorizationQuery["response_type"] == "code")
        #expect(authorizationQuery["state"] == "secure_state")
        #expect(authorizationQuery["scope"] == "api")
        #expect(authorizationQuery["code_challenge"] == pkce.codeChallenge)
        #expect(authorizationQuery["code_challenge_method"] == "S256")

        let tokenRequest = try configuration.authorizationCodeTokenRequest(
            code: "returned-code",
            codeVerifier: pkce.codeVerifier
        )
        let tokenForm = try formDictionary(tokenRequest)

        #expect(tokenRequest.url?.absoluteString == "https://gitlab.com/oauth/token")
        #expect(tokenRequest.httpMethod == "POST")
        #expect(
            tokenRequest.value(forHTTPHeaderField: "Content-Type")
                == "application/x-www-form-urlencoded"
        )
        #expect(tokenForm["client_id"] == "public-app-id")
        #expect(tokenForm["code"] == "returned-code")
        #expect(tokenForm["grant_type"] == "authorization_code")
        #expect(tokenForm["redirect_uri"] == "glab://oauth/callback")
        #expect(tokenForm["code_verifier"] == pkce.codeVerifier)
        #expect(tokenForm["client_secret"] == nil)
    }

    @Test("Builds OAuth paths relative to a self-managed GitLab installation")
    func buildsSelfManagedRequests() throws {
        let configuration = try GitLabOAuthConfiguration(
            instanceURL: "https://gitlab.example.com/company/gitlab/api/v4/",
            applicationID: "instance-app-id"
        )
        let pkce = try GitLabOAuthPKCE(
            state: "state",
            codeVerifier: String(repeating: "x", count: 43)
        )

        #expect(
            try configuration.authorizationURL(pkce: pkce)
                .absoluteString
                .hasPrefix(
                    "https://gitlab.example.com/company/gitlab/oauth/authorize?"
                )
        )
        #expect(
            try configuration.refreshTokenRequest(refreshToken: "refresh-secret")
                .url?
                .absoluteString
                == "https://gitlab.example.com/company/gitlab/oauth/token"
        )
        #expect(
            configuration.applicationSetupURL?.absoluteString
                == "https://gitlab.example.com/company/gitlab/-/user_settings/applications"
        )
    }

    @Test("Parses successful callbacks and rejects state or authorization failures")
    func parsesCallbacks() throws {
        let configuration = try GitLabOAuthConfiguration(
            instanceURL: "gitlab.com",
            applicationID: "application-id"
        )

        let code = try configuration.authorizationCode(
            from: try #require(
                URL(string: "glab://oauth/callback?code=code-123&state=state-123")
            ),
            expectedState: "state-123"
        )

        #expect(code == "code-123")
        #expect(throws: GitLabOAuthCallbackError.stateMismatch) {
            try configuration.authorizationCode(
                from: try #require(
                    URL(
                        string: "glab://oauth/callback?code=code-123&state=wrong"
                    )
                ),
                expectedState: "state-123"
            )
        }
        #expect(throws: GitLabOAuthCallbackError.accessDenied) {
            try configuration.authorizationCode(
                from: try #require(
                    URL(
                        string: "glab://oauth/callback?error=access_denied&state=state-123"
                    )
                ),
                expectedState: "state-123"
            )
        }
        #expect(throws: GitLabOAuthCallbackError.invalidCallback) {
            try configuration.authorizationCode(
                from: try #require(
                    URL(string: "other://oauth/callback?code=code-123&state=state-123")
                ),
                expectedState: "state-123"
            )
        }
    }

    @Test("Rejects malformed OAuth configuration")
    func rejectsMalformedConfiguration() {
        #expect(throws: GitLabOAuthConfigurationError.missingApplicationID) {
            try GitLabOAuthConfiguration(
                instanceURL: "gitlab.com",
                applicationID: " "
            )
        }
        #expect {
            try GitLabOAuthConfiguration(
                instanceURL: "http://gitlab.example.com",
                applicationID: "application-id"
            )
        } throws: { error in
            guard let configurationError = error as? GitLabOAuthConfigurationError else {
                return false
            }

            return configurationError
                == .invalidHost(.unsupportedScheme("http"))
        }
        #expect(throws: GitLabOAuthConfigurationError.invalidRedirectURI) {
            try GitLabOAuthConfiguration(
                instanceURL: "gitlab.com",
                applicationID: "application-id",
                redirectURI: URL(string: "other://oauth/callback")
            )
        }
    }
}

private extension GitLabOAuthFlowConstructionTests {
    nonisolated struct StubRandomBytesProvider:
        GitLabOAuthRandomBytesProviding,
        Sendable
    {
        let data: Data

        func randomBytes(
            count: Int
        ) throws(GitLabOAuthPKCEError) -> Data {
            data
        }
    }

    nonisolated func queryDictionary(
        _ queryItems: [URLQueryItem]?
    ) -> [String: String] {
        Dictionary(
            queryItems?.compactMap { item in
                item.value.map { (item.name, $0) }
            } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
    }

    nonisolated func formDictionary(
        _ request: URLRequest
    ) throws -> [String: String] {
        let body = try #require(request.httpBody)
        let bodyString = try #require(String(data: body, encoding: .utf8))
        let components = try #require(
            URLComponents(string: "https://example.com?\(bodyString)")
        )
        return queryDictionary(components.queryItems)
    }
}
