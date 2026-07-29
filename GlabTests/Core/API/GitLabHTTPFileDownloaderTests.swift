import Foundation
import Synchronization
import Testing
@testable import Glab

@Suite("GitLab HTTP file downloader")
struct GitLabHTTPFileDownloaderTests {
    @Test("Streams a successful response into a protected temporary file")
    func downloadsToProtectedFile() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let url = try testURL("success")
        let body = Data(
            repeating: 0x41,
            count: 131_073
        )
        ControlledFileURLProtocol.register(
            .init(
                response: try response(
                    url: url,
                    contentLength: body.count
                ),
                chunks: [body],
                finishes: true
            ),
            for: url
        )

        let result = try await downloader()
            .download(
                for: URLRequest(url: url),
                maximumByteCount: 200_000,
                temporaryDirectory: directory
            )

        #expect(result.byteCount == body.count)
        #expect(
            try Data(
                contentsOf: result.fileURL
            ) == body
        )
        #expect(
            !result.fileURL.lastPathComponent
                .contains("success")
        )
        let attributes = try FileManager
            .default
            .attributesOfItem(
                atPath: result.fileURL.path
            )
        let protection =
            attributes[
                FileAttributeKey
                    .protectionKey
            ] as? FileProtectionType
        #if targetEnvironment(simulator)
            #expect(
                protection == nil
                    || protection
                        == .completeUntilFirstUserAuthentication
            )
        #else
            #expect(
                protection
                    == .completeUntilFirstUserAuthentication
            )
        #endif
        let resourceValues =
            try result.fileURL.resourceValues(
                forKeys: [.isExcludedFromBackupKey]
            )
        #expect(
            resourceValues.isExcludedFromBackup
                == true
        )
    }

    @Test("Accepts an empty successful trace")
    func acceptsEmptyResponse() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let url = try testURL("empty")
        ControlledFileURLProtocol.register(
            .init(
                response: try response(
                    url: url,
                    contentLength: 0
                ),
                chunks: [],
                finishes: true
            ),
            for: url
        )

        let result = try await downloader()
            .download(
                for: URLRequest(url: url),
                maximumByteCount: 1,
                temporaryDirectory: directory
            )

        #expect(result.byteCount == 0)
        #expect(
            try Data(
                contentsOf: result.fileURL
            ).isEmpty
        )
    }

    @Test("Rejects an advertised response above the byte limit")
    func rejectsAdvertisedOverflow()
        async throws
    {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let url = try testURL(
            "advertised-overflow"
        )
        ControlledFileURLProtocol.register(
            .init(
                response: try response(
                    url: url,
                    contentLength: 6
                ),
                chunks: [],
                finishes: true
            ),
            for: url
        )

        await #expect {
            try await downloader().download(
                for: URLRequest(url: url),
                maximumByteCount: 5,
                temporaryDirectory: directory
            )
        } throws: { error in
            error as? GitLabHTTPFileDownloadError
                == .responseTooLarge
        }
        try expectDirectoryIsEmpty(directory)
    }

    @Test("Rejects observed bytes above the limit without a length")
    func rejectsObservedOverflow()
        async throws
    {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let url = try testURL(
            "observed-overflow"
        )
        ControlledFileURLProtocol.register(
            .init(
                response: try response(url: url),
                chunks: [
                    Data(
                        repeating: 0x41,
                        count: 6
                    ),
                ],
                finishes: true
            ),
            for: url
        )

        await #expect {
            try await downloader().download(
                for: URLRequest(url: url),
                maximumByteCount: 5,
                temporaryDirectory: directory
            )
        } throws: { error in
            error as? GitLabHTTPFileDownloadError
                == .responseTooLarge
        }
        try expectDirectoryIsEmpty(directory)
    }

    @Test("Rejects a truncated advertised response")
    func rejectsIncompleteResponse()
        async throws
    {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let url = try testURL("incomplete")
        ControlledFileURLProtocol.register(
            .init(
                response: try response(
                    url: url,
                    contentLength: 6
                ),
                chunks: [Data("short".utf8)],
                finishes: true
            ),
            for: url
        )

        await #expect {
            try await downloader().download(
                for: URLRequest(url: url),
                maximumByteCount: 10,
                temporaryDirectory: directory
            )
        } throws: { error in
            error as? GitLabHTTPFileDownloadError
                == .incompleteResponse
        }
        try expectDirectoryIsEmpty(directory)
    }

    @Test("Rejects HTTP failures without retaining their body")
    func rejectsHTTPFailure() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let url = try testURL("not-found")
        ControlledFileURLProtocol.register(
            .init(
                response: try response(
                    url: url,
                    statusCode: 404,
                    contentLength: 9
                ),
                chunks: [
                    Data("not found".utf8),
                ],
                finishes: true
            ),
            for: url
        )

        await #expect {
            try await downloader().download(
                for: URLRequest(url: url),
                maximumByteCount: 100,
                temporaryDirectory: directory
            )
        } throws: { error in
            error as? GitLabHTTPFileDownloadError
                == .unsuccessfulStatus(404)
        }
        try expectDirectoryIsEmpty(directory)
    }

    @Test("Maps network failure and removes the partial file")
    func cleansUpNetworkFailure()
        async throws
    {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let url = try testURL(
            "network-failure"
        )
        ControlledFileURLProtocol.register(
            .init(
                response: try response(url: url),
                chunks: [Data("partial".utf8)],
                finishes: false,
                failure:
                    URLError(
                        .networkConnectionLost
                    )
            ),
            for: url
        )

        await #expect {
            try await downloader().download(
                for: URLRequest(url: url),
                maximumByteCount: 100,
                temporaryDirectory: directory
            )
        } throws: { error in
            error as? GitLabHTTPFileDownloadError
                == .networkFailure
        }
        try expectDirectoryIsEmpty(directory)
    }

    @Test("Task cancellation removes the partial file")
    func cancellationCleansPartialFile()
        async throws
    {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let url = try testURL("cancel")
        let (
            delivered,
            deliveredContinuation
        ) = AsyncStream<Void>.makeStream()
        ControlledFileURLProtocol.register(
            .init(
                response: try response(url: url),
                chunks: [Data("partial".utf8)],
                finishes: false,
                didDeliverBody: {
                    deliveredContinuation
                        .yield()
                    deliveredContinuation
                        .finish()
                }
            ),
            for: url
        )
        let task = Task {
            try await downloader().download(
                for: URLRequest(url: url),
                maximumByteCount: 100,
                temporaryDirectory: directory
            )
        }

        for await _ in delivered {
            break
        }
        task.cancel()

        await #expect(
            throws: CancellationError.self
        ) {
            try await task.value
        }
        try expectDirectoryIsEmpty(directory)
    }

    @Test("Rejects invalid limits before creating a file")
    func rejectsInvalidLimit() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let url = try testURL("invalid-limit")

        await #expect {
            try await downloader().download(
                for: URLRequest(url: url),
                maximumByteCount: 0,
                temporaryDirectory: directory
            )
        } throws: { error in
            error as? GitLabHTTPFileDownloadError
                == .invalidConfiguration
        }
        try expectDirectoryIsEmpty(directory)
    }

    @Test("Rejects methods that could mutate server state")
    func rejectsNonGETRequest() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let url = try testURL("non-get")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        await #expect {
            try await downloader().download(
                for: request,
                maximumByteCount: 100,
                temporaryDirectory: directory
            )
        } throws: { error in
            error as? GitLabHTTPFileDownloadError
                == .invalidConfiguration
        }
        try expectDirectoryIsEmpty(directory)
    }

    private func downloader()
        -> URLSessionGitLabHTTPFileDownloader
    {
        URLSessionGitLabHTTPFileDownloader(
            protocolClasses: [
                ControlledFileURLProtocol.self
            ]
        )
    }

    private func response(
        url: URL,
        statusCode: Int = 200,
        contentLength: Int? = nil
    ) throws -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let contentLength {
            headers["Content-Length"] =
                String(contentLength)
        }
        return try #require(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        )
    }

    private func testURL(
        _ path: String
    ) throws -> URL {
        try #require(
            URL(
                string:
                    "https://download.test/"
                    + path
                    + "/\(UUID().uuidString)"
            )
        )
    }

    private func temporaryDirectory()
        throws -> URL
    {
        let directory =
            FileManager.default
            .temporaryDirectory
            .appending(
                path:
                    "GlabHTTPFileDownloaderTests-"
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

    private func expectDirectoryIsEmpty(
        _ directory: URL
    ) throws {
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
}

private nonisolated final class
    ControlledFileURLProtocol:
    URLProtocol
{
    nonisolated struct Plan: Sendable {
        let response: HTTPURLResponse
        let chunks: [Data]
        let finishes: Bool
        let failure: URLError?
        let didDeliverBody:
            (@Sendable () -> Void)?

        init(
            response: HTTPURLResponse,
            chunks: [Data],
            finishes: Bool,
            failure: URLError? = nil,
            didDeliverBody:
                (@Sendable () -> Void)? = nil
        ) {
            self.response = response
            self.chunks = chunks
            self.finishes = finishes
            self.failure = failure
            self.didDeliverBody =
                didDeliverBody
        }
    }

    private static let plans =
        Mutex<[String: Plan]>([:])

    static func register(
        _ plan: Plan,
        for url: URL
    ) {
        plans.withLock {
            $0[url.absoluteString] = plan
        }
    }

    override class func canInit(
        with request: URLRequest
    ) -> Bool {
        request.url != nil
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override class func requestIsCacheEquivalent(
        _ a: URLRequest,
        to b: URLRequest
    ) -> Bool {
        false
    }

    override func startLoading() {
        guard
            let key = request.url?
                .absoluteString,
            let plan =
                Self.plans.withLock({
                    $0.removeValue(
                        forKey: key
                    )
                })
        else {
            client?.urlProtocol(
                self,
                didFailWithError:
                    URLError(.badURL)
            )
            return
        }

        client?.urlProtocol(
            self,
            didReceive: plan.response,
            cacheStoragePolicy:
                .notAllowed
        )
        for chunk in plan.chunks {
            client?.urlProtocol(
                self,
                didLoad: chunk
            )
        }
        plan.didDeliverBody?()

        if let failure = plan.failure {
            client?.urlProtocol(
                self,
                didFailWithError: failure
            )
        } else if plan.finishes {
            client?.urlProtocolDidFinishLoading(
                self
            )
        }
    }

    override func stopLoading() {}
}
