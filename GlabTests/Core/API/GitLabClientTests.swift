import Foundation
import Testing
@testable import Glab

@Suite("GitLab client")
struct GitLabClientTests {
    @Test("Decodes an object and fractional ISO-8601 date")
    func decodesObject() async throws {
        let data = Data(
            #"{"id":7,"created_at":"2026-07-27T16:12:45.123Z"}"#.utf8
        )
        let client = try makeClient(
            outcome: .response(data, makeHTTPResponse(statusCode: 200))
        )

        let project = try await client.send(
            GitLabAPIRequest<TestProject>.get(
                requires: .read,
                path: ["projects", "7"]
            )
        )

        #expect(project.id == 7)
        #expect(
            abs(project.createdAt.timeIntervalSince1970 - 1_785_168_765.123) < 0.001
        )
    }

    @Test("Decodes an array response")
    func decodesArray() async throws {
        let data = Data(
            #"[{"id":1,"created_at":"2026-01-01T00:00:00Z"},{"id":2,"created_at":"2026-01-02T00:00:00Z"}]"#.utf8
        )
        let client = try makeClient(
            outcome: .response(data, makeHTTPResponse(statusCode: 200))
        )

        let projects = try await client.send(
            GitLabAPIRequest<[TestProject]>.get(
                requires: .read,
                path: ["projects"]
            )
        )

        #expect(projects.map(\.id) == [1, 2])
    }

    @Test("Handles a successful empty response")
    func handlesEmptyResponse() async throws {
        let client = try makeClient(
            outcome: .response(Data(), makeHTTPResponse(statusCode: 204))
        )

        let response = try await client.send(
            GitLabAPIRequest<GitLabEmptyResponse>.post(
                requires: .write,
                path: ["todos", "42", "mark_as_done"]
            )
        )

        #expect(response == GitLabEmptyResponse())
    }

    @Test("Maps malformed JSON to a decoding error")
    func mapsMalformedJSON() async throws {
        let client = try makeClient(
            outcome: .response(
                Data(#"{"id":"#.utf8),
                makeHTTPResponse(statusCode: 200)
            )
        )

        await #expect(throws: GitLabAPIError.decoding) {
            try await client.send(
                GitLabAPIRequest<TestProject>.get(
                    requires: .read,
                    path: ["projects", "7"]
                )
            )
        }
    }

    @Test("Returns request and next-page response metadata")
    func returnsResponseMetadata() async throws {
        let link = [
            "<https://gitlab.com/api/v4/projects?page=1&per_page=20>; rel=\"prev\"",
            "<https://gitlab.com/api/v4/projects?pagination=keyset&id_after=42>; rel=\"next\"",
            "<https://gitlab.com/api/v4/projects?page=1&per_page=20>; rel=\"first\"",
        ].joined(separator: ", ")
        let client = try makeClient(
            outcome: .response(
                Data("[]".utf8),
                makeHTTPResponse(
                    statusCode: 200,
                    headers: [
                        "Link": link,
                        "X-Request-ID": "request-123",
                    ]
                )
            )
        )

        let response = try await client.sendResponse(
            GitLabAPIRequest<[TestProject]>.get(
                requires: .read,
                path: ["projects"]
            )
        )

        #expect(response.value.isEmpty)
        #expect(response.metadata.requestID == "request-123")
        #expect(
            response.metadata.nextPageURL?.absoluteString
                == "https://gitlab.com/api/v4/projects?pagination=keyset&id_after=42"
        )
    }

    @Test("Captures safe validators for conditional cache revalidation")
    func capturesCacheValidators() async throws {
        let client = try makeClient(
            outcome: .response(
                Data("[]".utf8),
                makeHTTPResponse(
                    statusCode: 200,
                    headers: [
                        "ETag": " \"projects-v1\" ",
                        "Last-Modified":
                            " Mon, 27 Jul 2026 12:00:00 GMT ",
                    ]
                )
            )
        )

        let response = try await client.sendRawPage(
            GitLabAPIPageRequest<[TestProject]>
                .initial(
                    .get(
                        requires: .read,
                        path: ["projects"]
                    )
                )
        )

        #expect(response.entityTag == "\"projects-v1\"")
        #expect(
            response.lastModified
                == "Mon, 27 Jul 2026 12:00:00 GMT"
        )
    }

    @Test("Allows missing and malformed optional response metadata")
    func handlesOptionalResponseMetadata() async throws {
        let missingClient = try makeClient(
            outcome: .response(
                Data("[]".utf8),
                makeHTTPResponse(statusCode: 200)
            )
        )
        let malformedClient = try makeClient(
            outcome: .response(
                Data("[]".utf8),
                makeHTTPResponse(
                    statusCode: 200,
                    headers: [
                        "Link": "not-a-link; rel=\"next\"",
                        "X-Request-ID": "",
                    ]
                )
            )
        )

        let missing = try await missingClient.sendResponse(
            GitLabAPIRequest<[TestProject]>.get(
                requires: .read,
                path: ["projects"]
            )
        )
        let malformed = try await malformedClient.sendResponse(
            GitLabAPIRequest<[TestProject]>.get(
                requires: .read,
                path: ["projects"]
            )
        )

        #expect(missing.metadata == GitLabResponseMetadata())
        #expect(malformed.metadata == GitLabResponseMetadata())
    }

    @Test("Decodes a server-provided next page")
    func decodesNextPage() async throws {
        let data = Data(
            #"[{"id":2,"created_at":"2026-01-02T00:00:00Z"}]"#.utf8
        )
        let client = try makeClient(
            outcome: .response(
                data,
                makeHTTPResponse(statusCode: 200)
            )
        )
        let pageURL = try #require(
            URL(
                string:
                    "https://gitlab.com/api/v4/projects?page=2"
            )
        )

        let response = try await client.sendPage(
            GitLabAPIPageRequest<[TestProject]>.next(pageURL)
        )

        #expect(response.value.map(\.id) == [2])
    }

    @Test(
        "Parses Retry-After seconds",
        arguments: [
            ("30", GitLabAPIError.rateLimited(retryAfterSeconds: 30)),
            ("invalid", GitLabAPIError.rateLimited(retryAfterSeconds: nil)),
            ("-5", GitLabAPIError.rateLimited(retryAfterSeconds: nil)),
        ]
    )
    func parsesRetryAfter(header: String, expectedError: GitLabAPIError) async throws {
        let client = try makeClient(
            outcome: .response(
                Data("Retry later".utf8),
                makeHTTPResponse(
                    statusCode: 429,
                    headers: ["Retry-After": header]
                )
            )
        )

        await #expect(throws: expectedError) {
            try await client.send(
                GitLabAPIRequest<TestProject>.get(
                    requires: .read,
                    path: ["projects"]
                )
            )
        }
    }

    @Test(
        "Maps HTTP status codes",
        arguments: [
            (400, GitLabAPIError.validation(statusCode: 400)),
            (401, GitLabAPIError.unauthenticated),
            (403, GitLabAPIError.forbidden),
            (404, GitLabAPIError.notFound),
            (418, GitLabAPIError.http(statusCode: 418)),
            (422, GitLabAPIError.validation(statusCode: 422)),
            (429, GitLabAPIError.rateLimited(retryAfterSeconds: nil)),
            (500, GitLabAPIError.server(statusCode: 500)),
            (503, GitLabAPIError.server(statusCode: 503)),
        ]
    )
    func mapsHTTPStatus(statusCode: Int, expectedError: GitLabAPIError) async throws {
        let client = try makeClient(
            outcome: .response(
                Data(#"{"message":"request failed"}"#.utf8),
                makeHTTPResponse(statusCode: statusCode)
            )
        )

        await #expect(throws: expectedError) {
            try await client.send(
                GitLabAPIRequest<TestProject>.get(
                    requires: .read,
                    path: ["projects", "7"]
                )
            )
        }
    }

    @Test("Does not expose an error response body")
    func redactsErrorResponseBody() async throws {
        let secret = "never-expose-response-body"
        let client = try makeClient(
            outcome: .response(
                Data(#"{"message":"\#(secret)"}"#.utf8),
                makeHTTPResponse(statusCode: 400)
            )
        )

        do {
            _ = try await client.send(
                GitLabAPIRequest<TestProject>.get(
                    requires: .read,
                    path: ["projects", "7"]
                )
            )
            Issue.record("Expected the request to fail")
        } catch {
            #expect(!String(describing: error).contains(secret))
            #expect(!String(reflecting: error).contains(secret))
        }
    }

    @Test("Maps URL connectivity failures")
    func mapsConnectivityFailure() async throws {
        let client = try makeClient(
            outcome: .urlError(URLError(.notConnectedToInternet))
        )

        await #expect(
            throws: GitLabAPIError.connectivity(.notConnectedToInternet)
        ) {
            try await client.send(
                GitLabAPIRequest<TestProject>.get(
                    requires: .read,
                    path: ["projects"]
                )
            )
        }
    }

    @Test("Maps cancellation failures")
    func mapsCancellation() async throws {
        let cancelledClient = try makeClient(outcome: .cancellation)
        let urlCancelledClient = try makeClient(
            outcome: .urlError(URLError(.cancelled))
        )

        await #expect(throws: GitLabAPIError.cancelled) {
            try await cancelledClient.send(
                GitLabAPIRequest<TestProject>.get(
                    requires: .read,
                    path: ["projects"]
                )
            )
        }
        await #expect(throws: GitLabAPIError.cancelled) {
            try await urlCancelledClient.send(
                GitLabAPIRequest<TestProject>.get(
                    requires: .read,
                    path: ["projects"]
                )
            )
        }
    }

    @Test("A pre-cancelled request never reaches transport")
    func stopsBeforeTransportWhenAlreadyCancelled() async throws {
        let transport = CountingTransport(
            response: (
                Data(
                    #"{"id":7,"created_at":"2026-01-01T00:00:00Z"}"#.utf8
                ),
                try makeHTTPResponse(statusCode: 200)
            )
        )
        let client = try GitLabClient(
            requestBuilder: GitLabRequestBuilder(
                host: GitLabHost("gitlab.com"),
                authorization:
                    .oauth(accessToken: "oauth-secret")
            ),
            transport: transport
        )

        let result = await Task {
            () -> Result<TestProject, GitLabAPIError> in
            withUnsafeCurrentTask {
                $0?.cancel()
            }
            do {
                return .success(
                    try await client.send(
                        GitLabAPIRequest<TestProject>.get(
                            requires: .read,
                            path: ["projects", "7"]
                        )
                    )
                )
            } catch let error as GitLabAPIError {
                return .failure(error)
            } catch {
                return .failure(.transport)
            }
        }.value

        if case .failure(.cancelled) = result {
            // Expected.
        } else {
            Issue.record("Expected cancellation before transport")
        }
        #expect(await transport.requestCount == 0)
    }

    @Test("Maps invalid and unknown transport responses")
    func mapsOtherTransportFailures() async throws {
        let invalidResponseClient = try makeClient(
            outcome: .response(
                Data(),
                URLResponse(
                    url: try #require(URL(string: "https://gitlab.com/api/v4/projects")),
                    mimeType: nil,
                    expectedContentLength: 0,
                    textEncodingName: nil
                )
            )
        )
        let unknownFailureClient = try makeClient(outcome: .otherError)

        await #expect(throws: GitLabAPIError.invalidResponse) {
            try await invalidResponseClient.send(
                GitLabAPIRequest<TestProject>.get(
                    requires: .read,
                    path: ["projects"]
                )
            )
        }
        await #expect(throws: GitLabAPIError.transport) {
            try await unknownFailureClient.send(
                GitLabAPIRequest<TestProject>.get(
                    requires: .read,
                    path: ["projects"]
                )
            )
        }
    }

    @Test("Retries a transient GET and keeps the recorded backoff")
    func retriesTransientGet() async throws {
        let transport = SequenceTransport(
            outcomes: [
                .urlError(
                    URLError(.networkConnectionLost)
                ),
                .response(
                    Data(
                        #"{"id":7,"created_at":"2026-01-01T00:00:00Z"}"#.utf8
                    ),
                    try makeHTTPResponse(statusCode: 200)
                ),
            ]
        )
        let sleeper = RecordingSleeper()
        let client = try makeClient(
            transport: transport,
            sleep: { duration in
                await sleeper.record(duration)
            }
        )

        let project = try await client.send(
            GitLabAPIRequest<TestProject>.get(
                requires: .read,
                path: ["projects", "7"]
            )
        )

        #expect(project.id == 7)
        #expect(await transport.requestCount == 2)
        #expect(await sleeper.delays == [.milliseconds(500)])
    }

    @Test("Retries a transient next-page GET")
    func retriesTransientNextPage() async throws {
        let transport = SequenceTransport(
            outcomes: [
                .response(
                    Data(),
                    try makeHTTPResponse(statusCode: 503)
                ),
                .response(
                    Data("[]".utf8),
                    try makeHTTPResponse(statusCode: 200)
                ),
            ]
        )
        let sleeper = RecordingSleeper()
        let client = try makeClient(
            transport: transport,
            sleep: { duration in
                await sleeper.record(duration)
            }
        )
        let pageURL = try #require(
            URL(
                string:
                    "https://gitlab.com/api/v4/projects?page=2"
            )
        )

        let response = try await client.sendPage(
            GitLabAPIPageRequest<[TestProject]>.next(pageURL)
        )

        #expect(response.value.isEmpty)
        #expect(await transport.requestCount == 2)
        #expect(await sleeper.delays == [.milliseconds(500)])
    }

    @Test("Returns the final error after exhausting GET retries")
    func exhaustsTransientGetRetries() async throws {
        let transport = SequenceTransport(
            outcomes: [
                .urlError(
                    URLError(.networkConnectionLost)
                ),
                .response(
                    Data(),
                    try makeHTTPResponse(statusCode: 500)
                ),
                .response(
                    Data(),
                    try makeHTTPResponse(statusCode: 503)
                ),
            ]
        )
        let sleeper = RecordingSleeper()
        let client = try makeClient(
            transport: transport,
            sleep: { duration in
                await sleeper.record(duration)
            }
        )

        await #expect(
            throws: GitLabAPIError.server(statusCode: 503)
        ) {
            try await client.send(
                GitLabAPIRequest<TestProject>.get(
                    requires: .read,
                    path: ["projects"]
                )
            )
        }

        #expect(await transport.requestCount == 3)
        #expect(
            await sleeper.delays
                == [.milliseconds(500), .seconds(1)]
        )
    }

    @Test("Never retries a POST after a transient failure")
    func doesNotRetryPost() async throws {
        let transport = SequenceTransport(
            outcomes: [
                .urlError(URLError(.timedOut)),
                .response(
                    Data(),
                    try makeHTTPResponse(statusCode: 204)
                ),
            ]
        )
        let sleeper = RecordingSleeper()
        let client = try makeClient(
            transport: transport,
            sleep: { duration in
                await sleeper.record(duration)
            }
        )

        await #expect(
            throws: GitLabAPIError.connectivity(.timedOut)
        ) {
            try await client.send(
                GitLabAPIRequest<GitLabEmptyResponse>.post(
                    requires: .write,
                    path: ["todos", "42", "mark_as_done"]
                )
            )
        }

        #expect(await transport.requestCount == 1)
        #expect(await sleeper.delays.isEmpty)
    }

    @Test("Never retries a DELETE after a transient failure")
    func doesNotRetryDelete() async throws {
        let transport = SequenceTransport(
            outcomes: [
                .urlError(URLError(.timedOut)),
                .response(
                    Data(),
                    try makeHTTPResponse(statusCode: 204)
                ),
            ]
        )
        let sleeper = RecordingSleeper()
        let client = try makeClient(
            transport: transport,
            sleep: { duration in
                await sleeper.record(duration)
            }
        )

        await #expect(
            throws: GitLabAPIError.connectivity(.timedOut)
        ) {
            try await client.send(
                GitLabAPIRequest<GitLabEmptyResponse>.delete(
                    requires: .write,
                    path: [
                        "projects",
                        "42",
                        "issues",
                        "7",
                        "award_emoji",
                        "91",
                    ]
                )
            )
        }

        #expect(await transport.requestCount == 1)
        #expect(await sleeper.delays.isEmpty)
    }

    @Test(
        "Does not retry a timeout, offline, authentication, or rate-limit failure"
    )
    func doesNotRetryNontransientGet() async throws {
        let outcomes: [(StubOutcome, GitLabAPIError)] = [
            (
                .urlError(URLError(.timedOut)),
                .connectivity(.timedOut)
            ),
            (
                .urlError(URLError(.notConnectedToInternet)),
                .connectivity(.notConnectedToInternet)
            ),
            (
                .response(
                    Data(),
                    try makeHTTPResponse(statusCode: 401)
                ),
                .unauthenticated
            ),
            (
                .response(
                    Data(),
                    try makeHTTPResponse(statusCode: 403)
                ),
                .forbidden
            ),
            (
                .response(
                    Data(),
                    try makeHTTPResponse(
                        statusCode: 429,
                        headers: ["Retry-After": "30"]
                    )
                ),
                .rateLimited(retryAfterSeconds: 30)
            ),
        ]

        for (outcome, expectedError) in outcomes {
            let transport = SequenceTransport(
                outcomes: [outcome]
            )
            let sleeper = RecordingSleeper()
            let client = try makeClient(
                transport: transport,
                sleep: { duration in
                    await sleeper.record(duration)
                }
            )

            do {
                _ = try await client.send(
                    GitLabAPIRequest<TestProject>.get(
                        requires: .read,
                        path: ["projects", "7"]
                    )
                )
                Issue.record(
                    "Expected \(expectedError) to fail immediately"
                )
            } catch let error {
                #expect(error == expectedError)
            }

            #expect(await transport.requestCount == 1)
            #expect(await sleeper.delays.isEmpty)
        }
    }

    @Test("Cancellation during backoff stops before another request")
    func cancelsDuringBackoff() async throws {
        let transport = SequenceTransport(
            outcomes: [
                .urlError(
                    URLError(.networkConnectionLost)
                ),
                .response(
                    Data(
                        #"{"id":7,"created_at":"2026-01-01T00:00:00Z"}"#.utf8
                    ),
                    try makeHTTPResponse(statusCode: 200)
                ),
            ]
        )
        let sleeper = SuspendingSleeper()
        let client = try makeClient(
            transport: transport,
            sleep: { duration in
                try await sleeper.sleep(duration)
            }
        )
        let task = Task {
            () -> Result<TestProject, GitLabAPIError> in
            do {
                return .success(
                    try await client.send(
                        GitLabAPIRequest<TestProject>.get(
                            requires: .read,
                            path: ["projects", "7"]
                        )
                    )
                )
            } catch let error as GitLabAPIError {
                return .failure(error)
            } catch {
                return .failure(.transport)
            }
        }

        await sleeper.waitUntilStarted()
        task.cancel()
        let result = await task.value

        if case .failure(.cancelled) = result {
            // Expected.
        } else {
            Issue.record("Expected cancellation during backoff")
        }
        #expect(await transport.requestCount == 1)
    }
}

private extension GitLabClientTests {
    nonisolated struct TestProject: Decodable, Sendable {
        let id: Int
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case createdAt = "created_at"
        }
    }

    nonisolated struct StubError: Error, Sendable {}

    nonisolated enum StubOutcome: Sendable {
        case response(Data, URLResponse)
        case urlError(URLError)
        case cancellation
        case otherError
    }

    nonisolated struct StubTransport: GitLabHTTPTransport {
        let outcome: StubOutcome

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            switch outcome {
            case let .response(data, response):
                (data, response)
            case let .urlError(error):
                throw error
            case .cancellation:
                throw CancellationError()
            case .otherError:
                throw StubError()
            }
        }
    }

    actor CountingTransport: GitLabHTTPTransport {
        let response: (Data, URLResponse)
        private(set) var requestCount = 0

        init(response: (Data, URLResponse)) {
            self.response = response
        }

        func data(
            for request: URLRequest
        ) async throws -> (Data, URLResponse) {
            requestCount += 1
            return response
        }
    }

    actor SequenceTransport: GitLabHTTPTransport {
        private var outcomes: [StubOutcome]
        private(set) var requestCount = 0

        init(outcomes: [StubOutcome]) {
            self.outcomes = outcomes
        }

        func data(
            for request: URLRequest
        ) async throws -> (Data, URLResponse) {
            requestCount += 1
            guard !outcomes.isEmpty else {
                throw StubError()
            }

            let outcome = outcomes.removeFirst()
            switch outcome {
            case let .response(data, response):
                return (data, response)
            case let .urlError(error):
                throw error
            case .cancellation:
                throw CancellationError()
            case .otherError:
                throw StubError()
            }
        }
    }

    actor RecordingSleeper {
        private(set) var delays: [Duration] = []

        func record(_ duration: Duration) {
            delays.append(duration)
        }
    }

    actor SuspendingSleeper {
        private var didStart = false
        private var startContinuations:
            [CheckedContinuation<Void, Never>] = []

        func sleep(_ duration: Duration) async throws {
            didStart = true
            let continuations = startContinuations
            startContinuations.removeAll()
            for continuation in continuations {
                continuation.resume()
            }

            try await Task.sleep(for: .seconds(60))
        }

        func waitUntilStarted() async {
            guard !didStart else {
                return
            }

            await withCheckedContinuation { continuation in
                startContinuations.append(continuation)
            }
        }
    }

    nonisolated func makeClient(
        outcome: StubOutcome
    ) throws -> GitLabClient<StubTransport> {
        try GitLabClient(
            requestBuilder: GitLabRequestBuilder(
                host: GitLabHost("gitlab.com"),
                authorization: .oauth(accessToken: "oauth-secret")
            ),
            transport: StubTransport(outcome: outcome),
            sleep: { _ in }
        )
    }

    nonisolated func makeClient<Transport: GitLabHTTPTransport>(
        transport: Transport,
        sleep:
            @escaping @Sendable (Duration) async throws -> Void
    ) throws -> GitLabClient<Transport> {
        try GitLabClient(
            requestBuilder: GitLabRequestBuilder(
                host: GitLabHost("gitlab.com"),
                authorization: .oauth(accessToken: "oauth-secret")
            ),
            transport: transport,
            sleep: sleep
        )
    }

    nonisolated func makeHTTPResponse(
        statusCode: Int,
        headers: [String: String]? = nil
    ) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://gitlab.com/api/v4/projects"))

        return try #require(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/2",
                headerFields: headers
            )
        )
    }
}
