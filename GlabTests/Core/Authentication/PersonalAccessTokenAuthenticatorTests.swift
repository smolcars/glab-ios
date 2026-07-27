import Foundation
import Testing
@testable import Glab

@Suite("Personal access token authentication")
struct PersonalAccessTokenAuthenticatorTests {
    @Test("Validates GitLab.com and creates a read-write session")
    func authenticatesGitLabDotCom() async throws {
        let transport = StubTransport(
            responses: [
                .json(
                    """
                    {
                      "id": 42,
                      "username": "octocat",
                      "name": "The Octocat",
                      "avatar_url": "https://gitlab.com/uploads/avatar.png"
                    }
                    """
                ),
                .json(
                    """
                    {
                      "revoked": false,
                      "scopes": ["read_user", "api"],
                      "user_id": 42,
                      "active": true,
                      "expires_at": "2027-07-27"
                    }
                    """
                ),
            ]
        )
        let authenticator = GitLabPersonalAccessTokenAuthenticator(
            transport: transport
        )

        let session = try await authenticator.authenticate(
            instanceURL: "gitlab.com",
            token: "  pat-secret  \n"
        )
        let requests = await transport.recordedRequests()

        #expect(session.host.siteURL.absoluteString == "https://gitlab.com")
        #expect(session.user.username == "octocat")
        #expect(session.apiAccess == .readWrite)
        #expect(session.personalAccessTokenExpiresOn == "2027-07-27")
        #expect(session.personalAccessTokenMetadata?.scopes == ["api", "read_user"])
        #expect(requests.map(\.url?.path) == [
            "/api/v4/user",
            "/api/v4/personal_access_tokens/self",
        ])
        #expect(
            requests.allSatisfy {
                $0.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "pat-secret"
            }
        )
    }

    @Test("Normalizes a custom instance and creates a read-only session")
    func authenticatesCustomInstance() async throws {
        let transport = StubTransport(
            responses: [
                .json(
                    """
                    {
                      "id": 7,
                      "username": "tanuki",
                      "name": "Tanuki",
                      "avatar_url": null
                    }
                    """
                ),
                .json(
                    """
                    {
                      "revoked": false,
                      "scopes": ["read_api"],
                      "user_id": 7,
                      "active": true,
                      "expires_at": null
                    }
                    """
                ),
            ]
        )
        let authenticator = GitLabPersonalAccessTokenAuthenticator(
            transport: transport
        )

        let session = try await authenticator.authenticate(
            instanceURL: "https://gitlab.example.com//company/api/v4///",
            token: "pat-secret"
        )
        let requests = await transport.recordedRequests()

        #expect(
            session.host.siteURL.absoluteString
                == "https://gitlab.example.com/company"
        )
        #expect(session.apiAccess == .readOnly)
        #expect(session.personalAccessTokenExpiresOn == nil)
        #expect(requests.map(\.url?.absoluteString) == [
            "https://gitlab.example.com/company/api/v4/user",
            "https://gitlab.example.com/company/api/v4/personal_access_tokens/self",
        ])
    }

    @Test("Rejects malformed input before making a request")
    func rejectsMalformedInput() async {
        let transport = StubTransport(responses: [])
        let authenticator = GitLabPersonalAccessTokenAuthenticator(
            transport: transport
        )

        await #expect(
            throws: PersonalAccessTokenSignInError.invalidHost(
                .unsupportedScheme("http")
            )
        ) {
            try await authenticator.authenticate(
                instanceURL: "http://gitlab.example.com",
                token: "pat-secret"
            )
        }
        await #expect(throws: PersonalAccessTokenSignInError.emptyToken) {
            try await authenticator.authenticate(
                instanceURL: "gitlab.com",
                token: " \n"
            )
        }

        #expect(await transport.recordedRequests().isEmpty)
    }

    @Test("Maps rejected credentials and insufficient scopes")
    func rejectsInvalidCredentialsAndScopes() async {
        let unauthorizedTransport = StubTransport(
            responses: [.json("{}", statusCode: 401)]
        )
        let insufficientScopeTransport = StubTransport(
            responses: [
                .json(
                    """
                    {
                      "id": 42,
                      "username": "octocat",
                      "name": "The Octocat",
                      "avatar_url": null
                    }
                    """
                ),
                .json(
                    """
                    {
                      "revoked": false,
                      "scopes": ["read_user"],
                      "user_id": 42,
                      "active": true,
                      "expires_at": null
                    }
                    """
                ),
            ]
        )

        await #expect(throws: PersonalAccessTokenSignInError.invalidToken) {
            try await GitLabPersonalAccessTokenAuthenticator(
                transport: unauthorizedTransport
            ).authenticate(instanceURL: "gitlab.com", token: "rejected-secret")
        }
        await #expect(throws: PersonalAccessTokenSignInError.insufficientScope) {
            try await GitLabPersonalAccessTokenAuthenticator(
                transport: insufficientScopeTransport
            ).authenticate(instanceURL: "gitlab.com", token: "limited-secret")
        }
    }

    @Test("Maps unsupported token inspection and responses")
    func mapsUnsupportedServerBehavior() async {
        let unsupportedEndpointTransport = StubTransport(
            responses: [
                .json(
                    """
                    {
                      "id": 42,
                      "username": "octocat",
                      "name": "The Octocat",
                      "avatar_url": null
                    }
                    """
                ),
                .json("{}", statusCode: 404),
            ]
        )
        let malformedResponseTransport = StubTransport(
            responses: [.json(#"{"id":"not-an-integer"}"#)]
        )

        await #expect(
            throws: PersonalAccessTokenSignInError.unsupportedTokenInspection
        ) {
            try await GitLabPersonalAccessTokenAuthenticator(
                transport: unsupportedEndpointTransport
            ).authenticate(instanceURL: "gitlab.com", token: "pat-secret")
        }
        await #expect(throws: PersonalAccessTokenSignInError.unsupportedResponse) {
            try await GitLabPersonalAccessTokenAuthenticator(
                transport: malformedResponseTransport
            ).authenticate(instanceURL: "gitlab.com", token: "pat-secret")
        }
    }

    @Test("Never exposes the submitted token in errors")
    func redactsSubmittedToken() async {
        let secret = "never-print-this-personal-access-token"
        let transport = StubTransport(
            responses: [.json("{}", statusCode: 401)]
        )

        do {
            _ = try await GitLabPersonalAccessTokenAuthenticator(
                transport: transport
            ).authenticate(instanceURL: "gitlab.com", token: secret)
            Issue.record("Expected authentication to fail")
        } catch {
            #expect(!String(describing: error).contains(secret))
            #expect(!String(reflecting: error).contains(secret))
        }
    }
}

private extension PersonalAccessTokenAuthenticatorTests {
    nonisolated struct StubResponse: Sendable {
        let data: Data
        let statusCode: Int

        static func json(
            _ body: String,
            statusCode: Int = 200
        ) -> Self {
            Self(data: Data(body.utf8), statusCode: statusCode)
        }
    }

    actor StubTransport: GitLabHTTPTransport {
        private var responses: [StubResponse]
        private var requests: [URLRequest] = []

        init(responses: [StubResponse]) {
            self.responses = responses
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            guard !responses.isEmpty else {
                throw URLError(.badServerResponse)
            }

            let response = responses.removeFirst()
            let url = try #require(request.url)
            let httpResponse = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: response.statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response.data, httpResponse)
        }

        func recordedRequests() -> [URLRequest] {
            requests
        }
    }
}
