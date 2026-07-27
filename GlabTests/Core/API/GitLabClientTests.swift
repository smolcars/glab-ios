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

    nonisolated func makeClient(
        outcome: StubOutcome
    ) throws -> GitLabClient<StubTransport> {
        try GitLabClient(
            requestBuilder: GitLabRequestBuilder(
                host: GitLabHost("gitlab.com"),
                authorization: .oauth(accessToken: "oauth-secret")
            ),
            transport: StubTransport(outcome: outcome)
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
