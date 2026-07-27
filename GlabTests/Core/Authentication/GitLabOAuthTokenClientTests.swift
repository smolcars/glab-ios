import Foundation
import Testing
@testable import Glab

@Suite("GitLab OAuth token client")
struct GitLabOAuthTokenClientTests {
    @Test("Exchanges a code for rotating OAuth credentials")
    func exchangesAuthorizationCode() async throws {
        let transport = RecordingTransport(
            outcomes: [
                .response(
                    validTokenResponse(
                        accessToken: "access-one",
                        refreshToken: "refresh-one"
                    ),
                    try makeHTTPResponse(statusCode: 200)
                ),
            ]
        )
        let client = GitLabOAuthTokenClient(transport: transport)
        let configuration = try makeConfiguration()

        let credential = try await client.exchangeAuthorizationCode(
            configuration: configuration,
            code: "authorization-code",
            codeVerifier: String(repeating: "v", count: 64)
        )

        #expect(
            credential
                == (try GitLabCredential.oauth(
                    accessToken: "access-one",
                    refreshToken: "refresh-one",
                    expiresAt: Date(timeIntervalSince1970: 1_700_007_200)
                ))
        )

        let request = try #require(await transport.requests.first)
        let form = try formDictionary(request)

        #expect(request.url?.absoluteString == "https://gitlab.com/oauth/token")
        #expect(form["grant_type"] == "authorization_code")
        #expect(form["code"] == "authorization-code")
        #expect(form["code_verifier"] == String(repeating: "v", count: 64))
        #expect(form["client_secret"] == nil)
    }

    @Test("Refreshes and rotates both OAuth tokens")
    func refreshesTokens() async throws {
        let transport = RecordingTransport(
            outcomes: [
                .response(
                    validTokenResponse(
                        accessToken: "access-two",
                        refreshToken: "refresh-two"
                    ),
                    try makeHTTPResponse(statusCode: 200)
                ),
            ]
        )
        let client = GitLabOAuthTokenClient(transport: transport)

        let credential = try await client.refresh(
            configuration: makeConfiguration(),
            refreshToken: "refresh-one"
        )

        #expect(
            credential
                == (try GitLabCredential.oauth(
                    accessToken: "access-two",
                    refreshToken: "refresh-two",
                    expiresAt: Date(timeIntervalSince1970: 1_700_007_200)
                ))
        )

        let request = try #require(await transport.requests.first)
        let form = try formDictionary(request)

        #expect(form["grant_type"] == "refresh_token")
        #expect(form["refresh_token"] == "refresh-one")
        #expect(form["redirect_uri"] == "glab://oauth/callback")
        #expect(form["client_secret"] == nil)
    }

    @Test(
        "Maps documented OAuth endpoint errors",
        arguments: [
            ("invalid_client", GitLabOAuthTokenError.invalidApplication),
            ("invalid_grant", GitLabOAuthTokenError.invalidGrant),
            ("unauthorized_client", GitLabOAuthTokenError.applicationUnavailable),
            ("invalid_request", GitLabOAuthTokenError.invalidRequest),
            ("unsupported_grant_type", GitLabOAuthTokenError.invalidRequest),
        ]
    )
    func mapsEndpointErrors(
        code: String,
        expectedError: GitLabOAuthTokenError
    ) async throws {
        let transport = RecordingTransport(
            outcomes: [
                .response(
                    Data(#"{"error":"\#(code)","error_description":"redacted"}"#.utf8),
                    try makeHTTPResponse(statusCode: 400)
                ),
            ]
        )
        let client = GitLabOAuthTokenClient(transport: transport)

        await #expect(throws: expectedError) {
            try await client.refresh(
                configuration: makeConfiguration(),
                refreshToken: "refresh-secret"
            )
        }
    }

    @Test("Rejects malformed, non-Bearer, and incomplete token responses")
    func rejectsUnsupportedResponses() async throws {
        let malformed = RecordingTransport(
            outcomes: [
                .response(
                    Data(#"{"access_token":"secret"}"#.utf8),
                    try makeHTTPResponse(statusCode: 200)
                ),
            ]
        )
        let nonBearer = RecordingTransport(
            outcomes: [
                .response(
                    Data(
                        """
                        {
                          "access_token": "secret",
                          "token_type": "mac",
                          "expires_in": 7200,
                          "refresh_token": "refresh",
                          "created_at": 1700000000
                        }
                        """.utf8
                    ),
                    try makeHTTPResponse(statusCode: 200)
                ),
            ]
        )

        await #expect(throws: GitLabOAuthTokenError.unsupportedResponse) {
            try await GitLabOAuthTokenClient(transport: malformed).refresh(
                configuration: makeConfiguration(),
                refreshToken: "refresh"
            )
        }
        await #expect(throws: GitLabOAuthTokenError.unsupportedResponse) {
            try await GitLabOAuthTokenClient(transport: nonBearer).refresh(
                configuration: makeConfiguration(),
                refreshToken: "refresh"
            )
        }
    }

    @Test("Rejects OAuth timestamps that are negative or overflow")
    func rejectsInvalidTimestamps() async throws {
        let negativeTimestamp = RecordingTransport(
            outcomes: [
                .response(
                    tokenResponse(createdAt: -1, expiresIn: 7200),
                    try makeHTTPResponse(statusCode: 200)
                ),
            ]
        )
        let overflowingTimestamp = RecordingTransport(
            outcomes: [
                .response(
                    tokenResponse(createdAt: Int.max, expiresIn: 7200),
                    try makeHTTPResponse(statusCode: 200)
                ),
            ]
        )

        for transport in [negativeTimestamp, overflowingTimestamp] {
            await #expect(
                throws: GitLabOAuthTokenError.unsupportedResponse
            ) {
                try await GitLabOAuthTokenClient(
                    transport: transport
                )
                .refresh(
                    configuration: makeConfiguration(),
                    refreshToken: "refresh"
                )
            }
        }
    }

    @Test("Maps transport, cancellation, and server failures without response bodies")
    func mapsTransportFailures() async throws {
        let secret = "never-expose-oauth-response"
        let refreshToken = "never-expose-submitted-refresh-token"
        let server = RecordingTransport(
            outcomes: [
                .response(
                    Data(secret.utf8),
                    try makeHTTPResponse(statusCode: 503)
                ),
            ]
        )
        let connectivity = RecordingTransport(
            outcomes: [.urlError(URLError(.cannotConnectToHost))]
        )
        let cancellation = RecordingTransport(outcomes: [.cancellation])

        do {
            _ = try await GitLabOAuthTokenClient(transport: server).refresh(
                configuration: makeConfiguration(),
                refreshToken: refreshToken
            )
            Issue.record("Expected the server response to fail")
        } catch {
            let oauthError = try #require(error as? GitLabOAuthTokenError)
            #expect(oauthError == .server(statusCode: 503))
            #expect(!String(describing: error).contains(secret))
            #expect(!String(reflecting: error).contains(secret))
            #expect(!String(describing: error).contains(refreshToken))
            #expect(!String(reflecting: error).contains(refreshToken))
        }
        await #expect(
            throws: GitLabOAuthTokenError.connectivity(.cannotConnectToHost)
        ) {
            try await GitLabOAuthTokenClient(transport: connectivity).refresh(
                configuration: makeConfiguration(),
                refreshToken: "refresh"
            )
        }
        await #expect(throws: GitLabOAuthTokenError.cancelled) {
            try await GitLabOAuthTokenClient(transport: cancellation).refresh(
                configuration: makeConfiguration(),
                refreshToken: "refresh"
            )
        }
    }

    @Test("A pre-cancelled token exchange never reaches transport")
    func stopsBeforeTokenTransportWhenAlreadyCancelled() async throws {
        let transport = RecordingTransport(
            outcomes: [.cancellation]
        )
        let client = GitLabOAuthTokenClient(
            transport: transport
        )
        let configuration = try makeConfiguration()

        let error = await Task {
            () -> GitLabOAuthTokenError? in
            withUnsafeCurrentTask {
                $0?.cancel()
            }
            do {
                _ = try await client.refresh(
                    configuration: configuration,
                    refreshToken: "refresh"
                )
                return nil
            } catch let error as GitLabOAuthTokenError {
                return error
            } catch {
                return .transport
            }
        }.value

        #expect(error == .cancelled)
        #expect(await transport.requests.isEmpty)
    }
}

private extension GitLabOAuthTokenClientTests {
    actor RecordingTransport: GitLabHTTPTransport {
        nonisolated enum Outcome: Sendable {
            case response(Data, URLResponse)
            case urlError(URLError)
            case cancellation
        }

        private var outcomes: [Outcome]
        private(set) var requests: [URLRequest] = []

        init(outcomes: [Outcome]) {
            self.outcomes = outcomes
        }

        func data(
            for request: URLRequest
        ) async throws -> (Data, URLResponse) {
            requests.append(request)

            guard !outcomes.isEmpty else {
                throw URLError(.unknown)
            }

            let outcome = outcomes.removeFirst()
            switch outcome {
            case let .response(data, response):
                return (data, response)
            case let .urlError(error):
                throw error
            case .cancellation:
                throw CancellationError()
            }
        }
    }

    nonisolated func makeConfiguration() throws -> GitLabOAuthConfiguration {
        try GitLabOAuthConfiguration(
            instanceURL: "gitlab.com",
            applicationID: "application-id"
        )
    }

    nonisolated func validTokenResponse(
        accessToken: String,
        refreshToken: String
    ) -> Data {
        Data(
            """
            {
              "access_token": "\(accessToken)",
              "token_type": "Bearer",
              "expires_in": 7200,
              "refresh_token": "\(refreshToken)",
              "created_at": 1700000000
            }
            """.utf8
        )
    }

    nonisolated func tokenResponse(
        createdAt: Int,
        expiresIn: Int
    ) -> Data {
        Data(
            """
            {
              "access_token": "access",
              "token_type": "Bearer",
              "expires_in": \(expiresIn),
              "refresh_token": "refresh",
              "created_at": \(createdAt)
            }
            """.utf8
        )
    }

    nonisolated func makeHTTPResponse(
        statusCode: Int
    ) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://gitlab.com/oauth/token"))

        return try #require(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/2",
                headerFields: nil
            )
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

        return Dictionary(
            components.queryItems?.compactMap { item in
                item.value.map { (item.name, $0) }
            } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
    }
}
