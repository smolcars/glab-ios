import Foundation
import Testing
@testable import Glab

@Suite("GitLab OAuth refresh")
struct GitLabOAuthRefreshTests {
    @Test("Refreshes an expired session and persists both rotated tokens")
    func refreshesExpiredSession() async throws {
        let original = try makeOAuthSession(
            accessToken: "expired-access",
            refreshToken: "original-refresh",
            expiresAt: .distantPast
        )
        let rotatedCredential = try makeOAuthCredential(
            accessToken: "rotated-access",
            refreshToken: "rotated-refresh"
        )
        let store = InMemoryGitLabCredentialStore(session: original)
        let exchanger = StubTokenExchanger(outcome: .success(rotatedCredential))
        let transport = RecordingAPITransport(outcomes: [.success])
        let recorder = RefreshedSessionRecorder()
        let client = GitLabSessionClient(
            session: original,
            transport: transport,
            tokenExchanger: exchanger,
            credentialStore: store,
            sessionDidRefresh: { session in
                await recorder.record(session)
            }
        )

        let user: GitLabAuthenticatedUser = try await client.send(userRequest)
        let storedSession = try await store.load()

        #expect(user.username == "octocat")
        #expect(await exchanger.refreshTokens == ["original-refresh"])
        #expect(storedSession?.credential == rotatedCredential)
        #expect(await client.currentSession().credential == rotatedCredential)
        #expect(await recorder.sessions.map(\.credential) == [rotatedCredential])
        #expect(
            await transport.authorizationHeaders
                == ["Bearer rotated-access"]
        )
    }

    @Test("Stops before the API request when refresh fails")
    func reportsRefreshFailure() async throws {
        let session = try makeOAuthSession(expiresAt: .distantPast)
        let exchanger = StubTokenExchanger(
            outcome: .failure(.invalidGrant)
        )
        let transport = RecordingAPITransport(outcomes: [.success])
        let client = GitLabSessionClient(
            session: session,
            transport: transport,
            tokenExchanger: exchanger,
            credentialStore: InMemoryGitLabCredentialStore(session: session)
        )

        await #expect(
            throws: GitLabSessionClientError.refresh(
                .token(.invalidGrant)
            )
        ) {
            let _: GitLabAuthenticatedUser = try await client.send(userRequest)
        }
        #expect(await transport.requestCount == 0)
    }

    @Test("Refreshes after an unauthorized response and retries once")
    func retriesAfterUnauthorizedResponse() async throws {
        let session = try makeOAuthSession(expiresAt: .distantFuture)
        let exchanger = StubTokenExchanger(
            outcome: .success(
                try makeOAuthCredential(
                    accessToken: "rotated-access",
                    refreshToken: "rotated-refresh"
                )
            )
        )
        let transport = RecordingAPITransport(
            outcomes: [.unauthenticated, .success]
        )
        let client = GitLabSessionClient(
            session: session,
            transport: transport,
            tokenExchanger: exchanger,
            credentialStore: InMemoryGitLabCredentialStore(session: session)
        )

        let user: GitLabAuthenticatedUser = try await client.send(userRequest)

        #expect(user.id == 42)
        #expect(await exchanger.refreshCount == 1)
        #expect(
            await transport.authorizationHeaders
                == ["Bearer original-access", "Bearer rotated-access"]
        )
    }

    @Test("Retries the exact pagination link after OAuth refresh")
    func retriesPaginationLinkAfterUnauthorizedResponse() async throws {
        let session = try makeOAuthSession(expiresAt: .distantFuture)
        let exchanger = StubTokenExchanger(
            outcome: .success(
                try makeOAuthCredential(
                    accessToken: "rotated-access",
                    refreshToken: "rotated-refresh"
                )
            )
        )
        let transport = RecordingAPITransport(
            outcomes: [.unauthenticated, .success]
        )
        let client = GitLabSessionClient(
            session: session,
            transport: transport,
            tokenExchanger: exchanger,
            credentialStore: InMemoryGitLabCredentialStore(session: session)
        )
        let pageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/company/api/v4/issues?page=2"
            )
        )

        let response: GitLabAPIResponse<GitLabAuthenticatedUser> =
            try await client.sendPage(.next(pageURL))

        #expect(response.value.id == 42)
        #expect(await transport.requestURLs == [pageURL, pageURL])
        #expect(
            await transport.authorizationHeaders
                == ["Bearer original-access", "Bearer rotated-access"]
        )
    }

    @Test("Does not loop when the retried request is unauthorized")
    func limitsRetryToOne() async throws {
        let session = try makeOAuthSession(expiresAt: .distantFuture)
        let exchanger = StubTokenExchanger(
            outcome: .success(try makeOAuthCredential())
        )
        let transport = RecordingAPITransport(
            outcomes: [.unauthenticated, .unauthenticated, .success]
        )
        let client = GitLabSessionClient(
            session: session,
            transport: transport,
            tokenExchanger: exchanger,
            credentialStore: InMemoryGitLabCredentialStore(session: session)
        )

        await #expect(
            throws: GitLabSessionClientError.api(.unauthenticated)
        ) {
            let _: GitLabAuthenticatedUser = try await client.send(userRequest)
        }
        #expect(await exchanger.refreshCount == 1)
        #expect(await transport.requestCount == 2)
    }

    @Test("Coalesces simultaneous refresh attempts")
    func coalescesRefresh() async throws {
        let session = try makeOAuthSession(expiresAt: .distantPast)
        let credential = try makeOAuthCredential()
        let exchanger = GatedTokenExchanger(credential: credential)
        let transport = RecordingAPITransport(
            outcomes: [.success, .success]
        )
        let client = GitLabSessionClient(
            session: session,
            transport: transport,
            tokenExchanger: exchanger,
            credentialStore: InMemoryGitLabCredentialStore(session: session)
        )

        async let first: GitLabAuthenticatedUser = client.send(userRequest)
        async let second: GitLabAuthenticatedUser = client.send(userRequest)

        await exchanger.waitUntilRefreshStarts()
        #expect(await exchanger.refreshCount == 1)
        await exchanger.releaseRefresh()

        let users = try await [first, second]

        #expect(users.allSatisfy { $0.username == "octocat" })
        #expect(await exchanger.refreshCount == 1)
        #expect(await transport.requestCount == 2)
    }

    @Test("Does not restore credentials when sign-out wins a refresh race")
    func doesNotRestoreCredentialsAfterSignOut() async throws {
        let session = try makeOAuthSession(expiresAt: .distantPast)
        let exchanger = GatedTokenExchanger(
            credential: try makeOAuthCredential()
        )
        let store = InMemoryGitLabCredentialStore(session: session)
        let transport = RecordingAPITransport(outcomes: [.success])
        let client = GitLabSessionClient(
            session: session,
            transport: transport,
            tokenExchanger: exchanger,
            credentialStore: store
        )

        let request = Task {
            let user: GitLabAuthenticatedUser = try await client.send(
                userRequest
            )
            return user
        }
        await exchanger.waitUntilRefreshStarts()
        try await store.delete()
        await exchanger.releaseRefresh()

        await #expect(
            throws: GitLabSessionClientError.refresh(.invalidSession)
        ) {
            try await request.value
        }
        #expect(try await store.load() == nil)
        #expect(await transport.requestCount == 0)
    }
}

private extension GitLabOAuthRefreshTests {
    actor RefreshedSessionRecorder {
        private(set) var sessions: [GitLabStoredSession] = []

        func record(_ session: GitLabStoredSession) {
            sessions.append(session)
        }
    }

    nonisolated enum APIOutcome: Sendable {
        case success
        case unauthenticated
    }

    actor RecordingAPITransport: GitLabHTTPTransport {
        private var outcomes: [APIOutcome]
        private(set) var authorizationHeaders: [String] = []
        private(set) var requestURLs: [URL] = []

        var requestCount: Int {
            authorizationHeaders.count
        }

        init(outcomes: [APIOutcome]) {
            self.outcomes = outcomes
        }

        func data(
            for request: URLRequest
        ) async throws -> (Data, URLResponse) {
            requestURLs.append(request.url!)
            authorizationHeaders.append(
                request.value(forHTTPHeaderField: "Authorization") ?? ""
            )

            let outcome = outcomes.isEmpty
                ? APIOutcome.success
                : outcomes.removeFirst()
            let statusCode: Int
            let data: Data

            switch outcome {
            case .success:
                statusCode = 200
                data = Data(
                    """
                    {
                      "id": 42,
                      "username": "octocat",
                      "name": "The Octocat",
                      "avatar_url": null
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

    actor StubTokenExchanger: GitLabOAuthTokenExchanging {
        enum Outcome: Sendable {
            case success(GitLabCredential)
            case failure(GitLabOAuthTokenError)
        }

        private let outcome: Outcome
        private(set) var refreshTokens: [String] = []

        var refreshCount: Int {
            refreshTokens.count
        }

        init(outcome: Outcome) {
            self.outcome = outcome
        }

        func exchangeAuthorizationCode(
            configuration: GitLabOAuthConfiguration,
            code: String,
            codeVerifier: String
        ) async throws(GitLabOAuthTokenError) -> GitLabCredential {
            throw .invalidGrant
        }

        func refresh(
            configuration: GitLabOAuthConfiguration,
            refreshToken: String
        ) async throws(GitLabOAuthTokenError) -> GitLabCredential {
            refreshTokens.append(refreshToken)

            switch outcome {
            case let .success(credential):
                return credential
            case let .failure(error):
                throw error
            }
        }
    }

    actor GatedTokenExchanger: GitLabOAuthTokenExchanging {
        private let credential: GitLabCredential
        private var refreshContinuation: CheckedContinuation<Void, Never>?
        private var startContinuations: [CheckedContinuation<Void, Never>] = []
        private var isReleased = false
        private(set) var refreshCount = 0

        init(credential: GitLabCredential) {
            self.credential = credential
        }

        func exchangeAuthorizationCode(
            configuration: GitLabOAuthConfiguration,
            code: String,
            codeVerifier: String
        ) async throws(GitLabOAuthTokenError) -> GitLabCredential {
            throw .invalidGrant
        }

        func refresh(
            configuration: GitLabOAuthConfiguration,
            refreshToken: String
        ) async throws(GitLabOAuthTokenError) -> GitLabCredential {
            refreshCount += 1
            let continuations = startContinuations
            startContinuations.removeAll()
            continuations.forEach { $0.resume() }

            if !isReleased {
                await withCheckedContinuation { continuation in
                    refreshContinuation = continuation
                }
            }
            return credential
        }

        func waitUntilRefreshStarts() async {
            guard refreshCount == 0 else {
                return
            }

            await withCheckedContinuation { continuation in
                startContinuations.append(continuation)
            }
        }

        func releaseRefresh() {
            isReleased = true
            refreshContinuation?.resume()
            refreshContinuation = nil
        }
    }

    nonisolated var userRequest: GitLabAPIRequest<GitLabAuthenticatedUser> {
        .get(
            requires: .read,
            path: ["user"]
        )
    }

    nonisolated func makeOAuthCredential(
        accessToken: String = "rotated-access",
        refreshToken: String = "rotated-refresh"
    ) throws -> GitLabCredential {
        try GitLabCredential.oauth(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: .distantFuture
        )
    }

    nonisolated func makeOAuthSession(
        accessToken: String = "original-access",
        refreshToken: String = "original-refresh",
        expiresAt: Date
    ) throws -> GitLabStoredSession {
        try GitLabStoredSession(
            host: GitLabHost("https://gitlab.example.com/company"),
            user: GitLabUserSummary(
                id: 42,
                username: "octocat",
                name: "The Octocat",
                avatarURL: nil
            ),
            oauthApplicationID: "application-id",
            personalAccessTokenMetadata: nil,
            credential: GitLabCredential.oauth(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt
            )
        )
    }
}
