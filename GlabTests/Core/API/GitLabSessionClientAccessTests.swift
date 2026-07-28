import Foundation
import Testing
@testable import Glab

@Suite("GitLab session request access")
struct GitLabSessionClientAccessTests {
    @Test("Read-only sessions send reads but reject writes before transport")
    func rejectsUnsupportedWriteBeforeTransport() async throws {
        let transport = RecordingTransport()
        let client = try makeClient(
            scopes: ["read_api"],
            transport: transport
        )
        let readRequest =
            GitLabAPIRequest<TestResponse>.get(
                requires: .read,
                path: ["user"]
            )
        let writeRequest =
            GitLabAPIRequest<TestResponse>.post(
                requires: .write,
                path: ["todos", "42", "mark_as_done"]
            )

        let response = try await client.send(readRequest)

        #expect(response.value == "ok")
        #expect(await transport.requestCount == 1)

        await #expect(
            throws:
                GitLabSessionClientError
                    .insufficientAccess(required: .write)
        ) {
            let _: TestResponse = try await client.send(
                writeRequest
            )
        }

        #expect(await transport.requestCount == 1)
    }

    @Test("Read-write sessions send writes")
    func sendsSupportedWrite() async throws {
        let transport = RecordingTransport()
        let client = try makeClient(
            scopes: ["api"],
            transport: transport
        )

        let response: TestResponse = try await client.send(
            .post(
                requires: .write,
                path: ["todos", "42", "mark_as_done"]
            )
        )

        #expect(response.value == "ok")
        #expect(await transport.requestCount == 1)
        #expect(await transport.methods == ["POST"])
    }

    @Test("Read-only sessions reject PUT before transport")
    func rejectsPutBeforeTransport() async throws {
        let transport = RecordingTransport()
        let client = try makeClient(
            scopes: ["read_api"],
            transport: transport
        )

        await #expect(
            throws:
                GitLabSessionClientError
                    .insufficientAccess(required: .write)
        ) {
            let _: TestResponse = try await client.send(
                .put(
                    path: ["projects", "42", "issues", "7"],
                    query: [
                        URLQueryItem(
                            name: "state_event",
                            value: "close"
                        )
                    ]
                )
            )
        }

        #expect(await transport.requestCount == 0)
    }

    @Test("Read-write sessions send PUT once")
    func sendsSupportedPut() async throws {
        let transport = RecordingTransport()
        let client = try makeClient(
            scopes: ["api"],
            transport: transport
        )

        let response: TestResponse = try await client.send(
            .put(
                path: ["projects", "42", "issues", "7"],
                query: [
                    URLQueryItem(
                        name: "state_event",
                        value: "close"
                    )
                ]
            )
        )

        #expect(response.value == "ok")
        #expect(await transport.requestCount == 1)
        #expect(await transport.methods == ["PUT"])
    }

    @Test("Pagination is structurally read-only")
    func classifiesPaginationAsRead() throws {
        let url = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "todos?page=2"
            )
        )
        let page =
            GitLabAPIPageRequest<[TestResponse]>.next(url)

        #expect(page.requiredAccess == .read)
    }

    @Test("Insufficient access is actionable without forcing sign-in")
    func describesInsufficientAccess() {
        let error = GitLabSessionClientError
            .insufficientAccess(required: .write)

        #expect(!error.requiresReauthentication)
        #expect(
            error.description
                == "This action requires GitLab API write access. "
                + "Sign in with OAuth or a personal access token "
                + "that includes the api scope."
        )
    }
}

private extension GitLabSessionClientAccessTests {
    nonisolated struct TestResponse:
        Decodable,
        Equatable,
        Sendable
    {
        let value: String
    }

    actor RecordingTransport: GitLabHTTPTransport {
        private(set) var methods: [String] = []

        var requestCount: Int {
            methods.count
        }

        func data(
            for request: URLRequest
        ) async throws -> (Data, URLResponse) {
            methods.append(request.httpMethod ?? "")

            return (
                Data(#"{"value":"ok"}"#.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/2",
                    headerFields: nil
                )!
            )
        }
    }

    actor UnusedTokenExchanger:
        GitLabOAuthTokenExchanging
    {
        func exchangeAuthorizationCode(
            configuration: GitLabOAuthConfiguration,
            code: String,
            codeVerifier: String
        ) async throws(GitLabOAuthTokenError)
            -> GitLabCredential
        {
            throw .invalidGrant
        }

        func refresh(
            configuration: GitLabOAuthConfiguration,
            refreshToken: String
        ) async throws(GitLabOAuthTokenError)
            -> GitLabCredential
        {
            throw .invalidGrant
        }
    }

    nonisolated func makeClient(
        scopes: [String],
        transport: RecordingTransport
    ) throws -> GitLabSessionClient<
        RecordingTransport,
        UnusedTokenExchanger
    > {
        let session = try GitLabStoredSession(
            host: GitLabHost("gitlab.example.com"),
            user: GitLabUserSummary(
                id: 42,
                username: "octocat",
                name: "The Octocat",
                avatarURL: nil
            ),
            oauthApplicationID: nil,
            personalAccessTokenMetadata:
                GitLabPersonalAccessTokenMetadata(
                    scopes: scopes,
                    expiresOn: nil
                ),
            credential:
                GitLabCredential.personalAccessToken(
                    "pat-secret"
                )
        )

        return GitLabSessionClient(
            session: session,
            transport: transport,
            tokenExchanger: UnusedTokenExchanger(),
            credentialStore:
                InMemoryGitLabCredentialStore(
                    session: session
                )
        )
    }
}
