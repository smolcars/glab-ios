import Foundation
import Testing
@testable import Glab

@Suite("GitLab raw file session")
struct GitLabRawFileSessionTests {
    nonisolated enum FileOutcome:
        Equatable,
        Sendable
    {
        case success(Data)
        case status(Int)
        case tooLarge
        case incomplete
        case storage
        case unsafeRedirect
        case network
        case unauthorizedAndCancel
        case successAndCancel(Data)
    }

    @Test("Builds and downloads one authenticated read-only raw request")
    func downloadsAuthenticatedRawFile() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let transport = RecordingFileTransport(
            outcomes: [
                .success(Data("trace".utf8)),
            ]
        )
        let client = try makePATClient(
            transport: transport
        )

        let result = try await client
            .downloadRawFile(
                traceEndpoint(),
                maximumByteCount: 1_024,
                temporaryDirectory: directory
            )

        #expect(
            try Data(
                contentsOf: result.fileURL
            ) == Data("trace".utf8)
        )
        let calls = await transport.calls
        #expect(calls.count == 1)
        #expect(calls[0].request.httpMethod == "GET")
        #expect(
            calls[0].request.url?.absoluteString
                == "https://gitlab.example.com/company"
                + "/api/v4/projects/42/jobs/910/trace"
        )
        #expect(
            calls[0].request.value(
                forHTTPHeaderField: "Accept"
            )
                == "text/plain, application/octet-stream, */*"
        )
        #expect(
            calls[0].request.value(
                forHTTPHeaderField: "PRIVATE-TOKEN"
            ) == "pat-secret"
        )
        #expect(
            calls[0].request.value(
                forHTTPHeaderField: "Authorization"
            ) == nil
        )
        #expect(calls[0].maximumByteCount == 1_024)
        #expect(
            calls[0].temporaryDirectory
                .standardizedFileURL
                == directory.standardizedFileURL
        )
        #expect(await transport.jsonRequestCount == 0)
    }

    @Test("Refreshes expired OAuth before downloading")
    func proactivelyRefreshesOAuth() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let transport = RecordingFileTransport(
            outcomes: [
                .success(Data("trace".utf8)),
            ]
        )
        let exchanger = StubTokenExchanger(
            credential:
                try oauthCredential(
                    accessToken: "rotated-access",
                    refreshToken: "rotated-refresh"
                )
        )
        let client = try makeOAuthClient(
            expiresAt: .distantPast,
            transport: transport,
            exchanger: exchanger
        )

        _ = try await client.downloadRawFile(
            traceEndpoint(),
            maximumByteCount: 1_024,
            temporaryDirectory: directory
        )

        #expect(await exchanger.refreshCount == 1)
        #expect(
            await transport.authorizationHeaders
                == ["Bearer rotated-access"]
        )
    }

    @Test("Refreshes OAuth after one 401 and retries once")
    func reactivelyRefreshesOAuth() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let transport = RecordingFileTransport(
            outcomes: [
                .status(401),
                .success(Data("trace".utf8)),
            ]
        )
        let exchanger = StubTokenExchanger(
            credential:
                try oauthCredential(
                    accessToken: "rotated-access",
                    refreshToken: "rotated-refresh"
                )
        )
        let client = try makeOAuthClient(
            expiresAt: .distantFuture,
            transport: transport,
            exchanger: exchanger
        )

        _ = try await client.downloadRawFile(
            traceEndpoint(),
            maximumByteCount: 1_024,
            temporaryDirectory: directory
        )

        #expect(await exchanger.refreshCount == 1)
        #expect(
            await transport.authorizationHeaders
                == [
                    "Bearer original-access",
                    "Bearer rotated-access",
                ]
        )
        #expect(await transport.jsonRequestCount == 0)
    }

    @Test("Does not refresh a personal token after 401")
    func doesNotRefreshPAT() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let transport = RecordingFileTransport(
            outcomes: [.status(401)]
        )
        let client = try makePATClient(
            transport: transport
        )

        await #expect(
            throws:
                GitLabRawFileSessionError
                .session(
                    .api(.unauthenticated)
                )
        ) {
            _ = try await client.downloadRawFile(
                traceEndpoint(),
                maximumByteCount: 1_024,
                temporaryDirectory: directory
            )
        }

        #expect(await transport.calls.count == 1)
    }

    @Test("Never retries a second OAuth 401")
    func limitsReactiveRetryToOne() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let transport = RecordingFileTransport(
            outcomes: [
                .status(401),
                .status(401),
                .success(Data("unexpected".utf8)),
            ]
        )
        let exchanger = StubTokenExchanger(
            credential: try oauthCredential()
        )
        let client = try makeOAuthClient(
            expiresAt: .distantFuture,
            transport: transport,
            exchanger: exchanger
        )

        await #expect(
            throws:
                GitLabRawFileSessionError
                .session(
                    .api(.unauthenticated)
                )
        ) {
            _ = try await client.downloadRawFile(
                traceEndpoint(),
                maximumByteCount: 1_024,
                temporaryDirectory: directory
            )
        }

        #expect(await exchanger.refreshCount == 1)
        #expect(await transport.calls.count == 2)
    }

    @Test("Cancellation before the call avoids refresh and transport work")
    func cancellationBeforeCallStopsWork()
        async throws
    {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let transport = RecordingFileTransport(
            outcomes: [
                .success(Data("unexpected".utf8)),
            ]
        )
        let exchanger = StubTokenExchanger(
            credential: try oauthCredential()
        )
        let client = try makeOAuthClient(
            expiresAt: .distantPast,
            transport: transport,
            exchanger: exchanger
        )
        let task = Task {
            withUnsafeCurrentTask {
                $0?.cancel()
            }
            return try await client
                .downloadRawFile(
                    traceEndpoint(),
                    maximumByteCount:
                        1_024,
                    temporaryDirectory:
                        directory
                )
        }

        await #expect(
            throws:
                GitLabRawFileSessionError
                .session(
                    .api(.cancelled)
                )
        ) {
            try await task.value
        }
        #expect(await exchanger.refreshCount == 0)
        #expect(await transport.calls.isEmpty)
    }

    @Test("Cancellation after a 401 prevents OAuth refresh and retry")
    func cancellationAfter401StopsRetry()
        async throws
    {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let transport = RecordingFileTransport(
            outcomes: [
                .unauthorizedAndCancel,
                .success(Data("unexpected".utf8)),
            ]
        )
        let exchanger = StubTokenExchanger(
            credential: try oauthCredential()
        )
        let client = try makeOAuthClient(
            expiresAt: .distantFuture,
            transport: transport,
            exchanger: exchanger
        )
        let task = Task {
            try await client.downloadRawFile(
                traceEndpoint(),
                maximumByteCount: 1_024,
                temporaryDirectory: directory
            )
        }

        await #expect(
            throws:
                GitLabRawFileSessionError
                .session(
                    .api(.cancelled)
                )
        ) {
            try await task.value
        }

        #expect(await exchanger.refreshCount == 0)
        #expect(await transport.calls.count == 1)
    }

    @Test("Cancellation at transport completion removes the downloaded file")
    func cancellationAtCompletionRemovesFile()
        async throws
    {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let transport = RecordingFileTransport(
            outcomes: [
                .successAndCancel(
                    Data("discard me".utf8)
                ),
            ]
        )
        let client = try makePATClient(
            transport: transport
        )
        let task = Task {
            try await client.downloadRawFile(
                traceEndpoint(),
                maximumByteCount: 1_024,
                temporaryDirectory: directory
            )
        }

        await #expect(
            throws:
                GitLabRawFileSessionError
                .session(
                    .api(.cancelled)
                )
        ) {
            try await task.value
        }

        #expect(
            try FileManager.default
                .contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys:
                        nil
                )
                .isEmpty
        )
    }

    @Test(
        "Maps HTTP failures without response bodies",
        arguments: [
            (
                403,
                GitLabRawFileSessionError
                    .session(.api(.forbidden))
            ),
            (
                404,
                GitLabRawFileSessionError
                    .session(.api(.notFound))
            ),
            (
                429,
                GitLabRawFileSessionError
                    .session(
                        .api(
                            .rateLimited(
                                retryAfterSeconds:
                                    nil
                            )
                        )
                    )
            ),
            (
                503,
                GitLabRawFileSessionError
                    .session(
                        .api(
                            .server(
                                statusCode: 503
                            )
                        )
                    )
            ),
            (
                418,
                GitLabRawFileSessionError
                    .session(
                        .api(
                            .http(
                                statusCode: 418
                            )
                        )
                    )
            ),
        ]
    )
    func mapsHTTPStatus(
        status: Int,
        expected:
            GitLabRawFileSessionError
    ) async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let transport = RecordingFileTransport(
            outcomes: [.status(status)]
        )
        let client = try makePATClient(
            transport: transport
        )

        await #expect(throws: expected) {
            _ = try await client.downloadRawFile(
                traceEndpoint(),
                maximumByteCount: 1_024,
                temporaryDirectory: directory
            )
        }
    }

    @Test(
        "Maps bounded file failures to sanitized categories",
        arguments: [
            (
                FileOutcome.tooLarge,
                GitLabRawFileSessionError
                    .responseTooLarge
            ),
            (
                FileOutcome.incomplete,
                GitLabRawFileSessionError
                    .incompleteResponse
            ),
            (
                FileOutcome.storage,
                GitLabRawFileSessionError
                    .storageFailure
            ),
            (
                FileOutcome.unsafeRedirect,
                GitLabRawFileSessionError
                    .unsafeRedirect
            ),
            (
                FileOutcome.network,
                GitLabRawFileSessionError
                    .session(
                        .api(.transport)
                    )
            ),
        ]
    )
    func mapsFileFailure(
        outcome: FileOutcome,
        expected:
            GitLabRawFileSessionError
    ) async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let transport = RecordingFileTransport(
            outcomes: [outcome]
        )
        let client = try makePATClient(
            transport: transport
        )

        await #expect(throws: expected) {
            _ = try await client.downloadRawFile(
                traceEndpoint(),
                maximumByteCount: 1_024,
                temporaryDirectory: directory
            )
        }
        #expect(
            !expected.localizedDescription
                .contains(directory.path)
        )
        #expect(
            !expected.localizedDescription
                .contains("pat-secret")
        )
    }

    @Test("Raw file requests are not JSON-coalesced")
    func doesNotCoalesceDownloads() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let transport = RecordingFileTransport(
            outcomes: [
                .success(Data("first".utf8)),
                .success(Data("second".utf8)),
            ]
        )
        let client = try makePATClient(
            transport: transport
        )

        async let first = client.downloadRawFile(
            traceEndpoint(),
            maximumByteCount: 1_024,
            temporaryDirectory: directory
        )
        async let second = client.downloadRawFile(
            traceEndpoint(),
            maximumByteCount: 1_024,
            temporaryDirectory: directory
        )
        _ = try await [first, second]

        #expect(await transport.calls.count == 2)
        #expect(await transport.jsonRequestCount == 0)
    }
}

private extension GitLabRawFileSessionTests {
    nonisolated struct FileCall:
        Sendable
    {
        let request: URLRequest
        let maximumByteCount: Int
        let temporaryDirectory: URL
    }

    actor RecordingFileTransport:
        GitLabHTTPTransport,
        GitLabHTTPFileDownloading
    {
        private var outcomes:
            [FileOutcome]
        private(set) var calls:
            [FileCall] = []
        private(set) var jsonRequestCount = 0

        var authorizationHeaders:
            [String]
        {
            calls.map {
                $0.request.value(
                    forHTTPHeaderField:
                        "Authorization"
                ) ?? ""
            }
        }

        init(outcomes: [FileOutcome]) {
            self.outcomes = outcomes
        }

        func data(
            for request: URLRequest
        ) async throws -> (
            Data,
            URLResponse
        ) {
            jsonRequestCount += 1
            throw URLError(.unsupportedURL)
        }

        func download(
            for request: URLRequest,
            maximumByteCount: Int,
            temporaryDirectory: URL
        ) async throws
            -> GitLabHTTPDownloadedFile
        {
            calls.append(
                FileCall(
                    request: request,
                    maximumByteCount:
                        maximumByteCount,
                    temporaryDirectory:
                        temporaryDirectory
                )
            )
            let outcome = outcomes.isEmpty
                ? FileOutcome.network
                : outcomes.removeFirst()

            switch outcome {
            case let .success(body):
                return try successfulFile(
                    body,
                    request: request,
                    temporaryDirectory:
                        temporaryDirectory
                )
            case let .status(status):
                throw
                    GitLabHTTPFileDownloadError
                    .unsuccessfulStatus(status)
            case .tooLarge:
                throw
                    GitLabHTTPFileDownloadError
                    .responseTooLarge
            case .incomplete:
                throw
                    GitLabHTTPFileDownloadError
                    .incompleteResponse
            case .storage:
                throw
                    GitLabHTTPFileDownloadError
                    .storageFailure
            case .unsafeRedirect:
                throw
                    GitLabHTTPFileRedirectError
                    .unsafeDestination
            case .network:
                throw
                    GitLabHTTPFileDownloadError
                    .networkFailure
            case .unauthorizedAndCancel:
                withUnsafeCurrentTask {
                    $0?.cancel()
                }
                throw
                    GitLabHTTPFileDownloadError
                    .unsuccessfulStatus(401)
            case let .successAndCancel(
                body
            ):
                let file = try successfulFile(
                    body,
                    request: request,
                    temporaryDirectory:
                        temporaryDirectory
                )
                withUnsafeCurrentTask {
                    $0?.cancel()
                }
                return file
            }
        }

        private func successfulFile(
            _ body: Data,
            request: URLRequest,
            temporaryDirectory: URL
        ) throws -> GitLabHTTPDownloadedFile {
            let fileURL =
                temporaryDirectory
                .appending(
                    path:
                        "raw-session-test-"
                        + UUID().uuidString,
                    directoryHint:
                        .notDirectory
                )
            try body.write(to: fileURL)
            return GitLabHTTPDownloadedFile(
                fileURL: fileURL,
                response:
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion:
                            "HTTP/2",
                        headerFields: nil
                    )!,
                byteCount: body.count
            )
        }
    }

    actor StubTokenExchanger:
        GitLabOAuthTokenExchanging
    {
        private let credential:
            GitLabCredential
        private(set) var refreshCount = 0

        init(credential: GitLabCredential) {
            self.credential = credential
        }

        func exchangeAuthorizationCode(
            configuration:
                GitLabOAuthConfiguration,
            code: String,
            codeVerifier: String
        ) async throws(GitLabOAuthTokenError)
            -> GitLabCredential
        {
            throw .invalidGrant
        }

        func refresh(
            configuration:
                GitLabOAuthConfiguration,
            refreshToken: String
        ) async throws(GitLabOAuthTokenError)
            -> GitLabCredential
        {
            refreshCount += 1
            return credential
        }
    }

    nonisolated func makePATClient(
        transport: RecordingFileTransport
    ) throws -> GitLabSessionClient<
        RecordingFileTransport,
        StubTokenExchanger
    > {
        let session = try GitLabStoredSession(
            host:
                GitLabHost(
                    "https://gitlab.example.com/company"
                ),
            user: testUser,
            oauthApplicationID: nil,
            personalAccessTokenMetadata:
                GitLabPersonalAccessTokenMetadata(
                    scopes: ["read_api"],
                    expiresOn: nil
                ),
            credential:
                GitLabCredential
                .personalAccessToken(
                    "pat-secret"
                )
        )
        return GitLabSessionClient(
            session: session,
            transport: transport,
            tokenExchanger:
                StubTokenExchanger(
                    credential:
                        try oauthCredential()
                ),
            credentialStore:
                InMemoryGitLabCredentialStore(
                    session: session
                )
        )
    }

    nonisolated func makeOAuthClient(
        expiresAt: Date,
        transport: RecordingFileTransport,
        exchanger: StubTokenExchanger
    ) throws -> GitLabSessionClient<
        RecordingFileTransport,
        StubTokenExchanger
    > {
        let session = try GitLabStoredSession(
            host:
                GitLabHost(
                    "https://gitlab.example.com/company"
                ),
            user: testUser,
            oauthApplicationID:
                "application-id",
            personalAccessTokenMetadata: nil,
            credential:
                try oauthCredential(
                    accessToken:
                        "original-access",
                    refreshToken:
                        "original-refresh",
                    expiresAt: expiresAt
                )
        )
        return GitLabSessionClient(
            session: session,
            transport: transport,
            tokenExchanger: exchanger,
            credentialStore:
                InMemoryGitLabCredentialStore(
                    session: session
                )
        )
    }

    nonisolated func oauthCredential(
        accessToken: String =
            "rotated-access",
        refreshToken: String =
            "rotated-refresh",
        expiresAt: Date =
            .distantFuture
    ) throws -> GitLabCredential {
        try GitLabCredential.oauth(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }

    nonisolated var testUser:
        GitLabUserSummary
    {
        GitLabUserSummary(
            id: 42,
            username: "octocat",
            name: "The Octocat",
            avatarURL: nil
        )
    }

    nonisolated func traceEndpoint()
        -> GitLabRawAPIRequest
    {
        GitLabJobTraceEndpoints.trace(
            at:
                GitLabJobTraceRoute(
                    projectID: 42,
                    jobID: 910
                )!
        )
    }

    nonisolated func temporaryDirectory()
        throws -> URL
    {
        let directory =
            FileManager.default
            .temporaryDirectory
            .appending(
                path:
                    "GlabRawFileSessionTests-"
                    + UUID().uuidString,
                directoryHint: .isDirectory
            )
        try FileManager.default
            .createDirectory(
                at: directory,
                withIntermediateDirectories:
                    false
            )
        return directory
    }
}
