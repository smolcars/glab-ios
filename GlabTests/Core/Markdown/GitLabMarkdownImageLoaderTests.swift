import Foundation
import Testing
@testable import Glab

@Suite("GitLab Markdown image request policy")
struct GitLabMarkdownImageRequestPolicyTests {
    @Test("Adds OAuth authorization only to the exact GitLab origin")
    func exactOriginOAuthAuthorization() throws {
        let policy = GitLabMarkdownImageRequestPolicy(
            host: try GitLabHost(
                "https://gitlab.example.com/gitlab"
            ),
            authorization: .oauth(
                accessToken: "oauth-secret"
            )
        )

        let sameOrigin = try #require(
            policy.request(
                for: URL(
                    string:
                        "https://gitlab.example.com/uploads/image.png"
                )!
            )
        )
        #expect(
            sameOrigin.value(
                forHTTPHeaderField: "Authorization"
            ) == "Bearer oauth-secret"
        )
        #expect(
            sameOrigin.value(
                forHTTPHeaderField: "PRIVATE-TOKEN"
            ) == nil
        )

        let external = try #require(
            policy.request(
                for: URL(
                    string:
                        "https://images.example.com/image.png"
                )!
            )
        )
        #expect(
            external.value(
                forHTTPHeaderField: "Authorization"
            ) == nil
        )
        #expect(
            external.value(
                forHTTPHeaderField: "PRIVATE-TOKEN"
            ) == nil
        )
    }

    @Test("Adds a personal token only to the exact GitLab origin")
    func exactOriginPersonalTokenAuthorization() throws {
        let policy = GitLabMarkdownImageRequestPolicy(
            host: try GitLabHost(
                "https://gitlab.example.com"
            ),
            authorization: .personalAccessToken(
                "pat-secret"
            )
        )

        let sameOrigin = try #require(
            policy.request(
                for: URL(
                    string:
                        "https://gitlab.example.com/uploads/image.png"
                )!
            )
        )
        #expect(
            sameOrigin.value(
                forHTTPHeaderField: "PRIVATE-TOKEN"
            ) == "pat-secret"
        )

        let siblingHost = try #require(
            policy.request(
                for: URL(
                    string:
                        "https://cdn.gitlab.example.com/image.png"
                )!
            )
        )
        #expect(
            siblingHost.value(
                forHTTPHeaderField: "PRIVATE-TOKEN"
            ) == nil
        )
    }

    @Test("Rebuilds safe redirects without inherited credentials")
    func redirectAuthorization() throws {
        let policy = GitLabMarkdownImageRequestPolicy(
            host: try GitLabHost(
                "https://gitlab.example.com"
            ),
            authorization: .personalAccessToken(
                "pat-secret"
            )
        )

        let sameOrigin = try #require(
            policy.redirectedRequest(
                to: URL(
                    string:
                        "https://gitlab.example.com/uploads/final.png"
                )!
            )
        )
        #expect(
            sameOrigin.value(
                forHTTPHeaderField: "PRIVATE-TOKEN"
            ) == "pat-secret"
        )

        let external = try #require(
            policy.redirectedRequest(
                to: URL(
                    string:
                        "https://cdn.example.com/final.png"
                )!
            )
        )
        #expect(
            external.value(
                forHTTPHeaderField: "Authorization"
            ) == nil
        )
        #expect(
            external.value(
                forHTTPHeaderField: "PRIVATE-TOKEN"
            ) == nil
        )

        #expect(
            policy.redirectedRequest(
                to: URL(
                    string:
                        "http://gitlab.example.com/final.png"
                )!
            ) == nil
        )
        #expect(
            policy.redirectedRequest(
                to: URL(
                    string:
                        "https://user:pass@gitlab.example.com/final.png"
                )!
            ) == nil
        )
    }
}

@Suite("GitLab Markdown image loader")
struct GitLabMarkdownImageLoaderTests {
    @Test("Validates source dimensions and decodes a bounded image")
    func dimensionValidationAndDecode() async throws {
        #expect(
            GitLabMarkdownImageDecoder
                .hasValidPixelDimensions(
                    width: 4_000,
                    height: 4_000,
                    maximumPixelCount: 16_000_000
                )
        )
        #expect(
            !GitLabMarkdownImageDecoder
                .hasValidPixelDimensions(
                    width: 4_001,
                    height: 4_000,
                    maximumPixelCount: 16_000_000
                )
        )
        #expect(
            !GitLabMarkdownImageDecoder
                .hasValidPixelDimensions(
                    width: 0,
                    height: 100,
                    maximumPixelCount: 16_000_000
                )
        )

        let image = try await GitLabMarkdownImageDecoder
            .decode(
                pngData,
                targetPixelWidth: 128,
                maximumPixelCount: 16_000_000
            )

        #expect(image.pixelWidth == 1)
        #expect(image.pixelHeight == 1)
        #expect(image.decodedCost > 0)
    }

    @Test("Rasterizes SVG images within the requested bounds")
    func svgDecode() async throws {
        let svg = Data(
            """
            \u{feff}<!-- generated badge -->
            <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">
              <rect width="200" height="100" fill="#2da44e"/>
              <text x="100" y="58" text-anchor="middle" fill="white">passing</text>
            </svg>
            """.utf8
        )

        let image = try await GitLabMarkdownImageDecoder
            .decode(
                svg,
                targetPixelWidth: 256,
                maximumPixelCount: 16_000_000
            )

        #expect(image.pixelWidth == 256)
        #expect(image.pixelHeight == 128)
        #expect(image.decodedCost > 0)
    }

    @Test("Rasterizes SVG badges with embedded SVG logos")
    func svgBadgeWithEmbeddedLogo() async throws {
        let nestedLogo = Data(
            """
            <svg fill="#F03C2E" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
              <title>Git</title>
              <path d="M0 0h24v24H0z"/>
            </svg>
            """.utf8
        )
        .base64EncodedString()
        let svg = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="107" height="20">
              <rect width="107" height="20" fill="#555"/>
              <image x="5" y="3" width="14" height="14" href="data:image/svg+xml;base64,\(nestedLogo)"/>
              <text x="60" y="14" fill="white">PRs welcome</text>
            </svg>
            """.utf8
        )

        let normalized = String(
            data: GitLabMarkdownImageDecoder
                .normalizeSVGForSwiftDraw(svg),
            encoding: .utf8
        )
        #expect(
            normalized?.contains(
                "data:image/svg+xml"
            ) == false
        )
        #expect(
            normalized?.contains(
                "xlink:href=\"data:image/png;base64,"
            ) == true
        )

        let image = try await GitLabMarkdownImageDecoder
            .decode(
                svg,
                targetPixelWidth: 321,
                maximumPixelCount: 16_000_000
            )

        #expect(image.pixelWidth == 321)
        #expect(image.pixelHeight == 60)
    }

    @Test("Rejects malformed SVG data")
    func malformedSVG() async {
        let svg = Data(
            "<svg><not-closed>".utf8
        )

        await #expect(
            throws:
                GitLabMarkdownImageError.invalidImage
        ) {
            try await GitLabMarkdownImageDecoder
                .decode(
                    svg,
                    targetPixelWidth: 256,
                    maximumPixelCount: 16_000_000
                )
        }
    }

    @Test("Rejects non-image MIME types and malformed image data")
    func contentValidation() async throws {
        let nonImageTransport =
            ControlledMarkdownImageTransport(
                result: .success(
                    response(
                        data: pngData,
                        contentType: "text/plain"
                    )
                )
            )
        let nonImageLoader = try makeLoader(
            transport: nonImageTransport
        )

        await #expect(
            throws:
                GitLabMarkdownImageError
                    .invalidContentType
        ) {
            try await nonImageLoader.image(
                request()
            )
        }

        let malformedTransport =
            ControlledMarkdownImageTransport(
                result: .success(
                    response(
                        data: Data("not an image".utf8),
                        contentType: "image/png"
                    )
                )
            )
        let malformedLoader = try makeLoader(
            transport: malformedTransport
        )

        await #expect(
            throws:
                GitLabMarkdownImageError
                    .invalidImage
        ) {
            try await malformedLoader.image(
                request()
            )
        }
    }

    @Test("Enforces the byte limit even without a truthful length header")
    func byteLimit() async throws {
        let noLengthTransport =
            ControlledMarkdownImageTransport(
                result: .success(
                    response(
                        data: pngData,
                        contentType: "image/png"
                    )
                )
            )
        let noLengthLoader = try makeLoader(
            transport: noLengthTransport,
            maximumDownloadByteCount:
                pngData.count - 1
        )

        await #expect(
            throws:
                GitLabMarkdownImageError
                    .byteLimitExceeded
        ) {
            try await noLengthLoader.image(
                request()
            )
        }

        let falseLengthTransport =
            ControlledMarkdownImageTransport(
                result: .success(
                    response(
                        data: pngData,
                        contentType: "image/png",
                        contentLength: "1"
                    )
                )
            )
        let falseLengthLoader = try makeLoader(
            transport: falseLengthTransport,
            maximumDownloadByteCount:
                pngData.count - 1
        )

        await #expect(
            throws:
                GitLabMarkdownImageError
                    .byteLimitExceeded
        ) {
            try await falseLengthLoader.image(
                request()
            )
        }
    }

    @Test("Caches images with count and decoded-cost bounds")
    func boundedCache() async throws {
        let transport =
            ControlledMarkdownImageTransport(
                result: .success(
                    response(
                        data: pngData,
                        contentType: "image/png"
                    )
                )
            )
        let loader = try makeLoader(
            transport: transport,
            maximumImageCount: 1,
            maximumDecodedCost: 1_024
        )
        let first = request(
            url:
                "https://gitlab.example.com/uploads/first.png"
        )
        let second = request(
            url:
                "https://gitlab.example.com/uploads/second.png"
        )

        _ = try await loader.image(first)
        _ = try await loader.image(first)
        #expect(await transport.callCount == 1)

        _ = try await loader.image(second)
        _ = try await loader.image(first)

        #expect(await transport.callCount == 3)
        #expect(await loader.cacheEntryCount == 1)
        #expect(await loader.cacheDecodedCost <= 1_024)
    }

    @Test("Restores a fresh image from the persistent response cache")
    func persistentCache() async throws {
        let now = Date(
            timeIntervalSince1970: 10_000
        )
        let persistentCache =
            InMemoryGitLabResponseCache()
        let networkTransport =
            ControlledMarkdownImageTransport(
                result: .success(
                    response(
                        data: pngData,
                        contentType: "image/png"
                    )
                )
            )
        let firstLoader = try makeLoader(
            transport: networkTransport,
            persistentResponseCache:
                persistentCache,
            persistentCachePolicy: .profile,
            currentDate: { now }
        )

        _ = try await firstLoader.image(request())
        #expect(await networkTransport.callCount == 1)

        let unavailableTransport =
            ControlledMarkdownImageTransport(
                result: .failure(
                    GitLabMarkdownImageError
                        .networkFailure
                )
            )
        let restoredLoader = try makeLoader(
            transport: unavailableTransport,
            persistentResponseCache:
                persistentCache,
            persistentCachePolicy: .profile,
            currentDate: {
                now.addingTimeInterval(60 * 60)
            }
        )

        let restored = try await restoredLoader.image(
            request()
        )

        #expect(restored.pixelWidth == 1)
        #expect(await unavailableTransport.callCount == 0)
    }

    @Test("Coalesces identical requests and cancels the last waiter")
    func coalescingAndCancellation() async throws {
        let transport =
            GatedMarkdownImageTransport(
                response: response(
                    data: pngData,
                    contentType: "image/png"
                )
            )
        let loader = try makeLoader(
            transport: transport
        )
        let loadRequest = request()

        async let first = loader.image(loadRequest)
        async let second = loader.image(loadRequest)
        await transport.waitUntilStarted()

        #expect(await transport.callCount == 1)
        #expect(await loader.inFlightCount == 1)
        await transport.finish()

        _ = try await [first, second]
        #expect(await loader.cacheEntryCount == 1)
        #expect(await loader.inFlightCount == 0)

        let cancellationTransport =
            GatedMarkdownImageTransport(
                response: response(
                    data: pngData,
                    contentType: "image/png"
                )
            )
        let cancellationLoader = try makeLoader(
            transport: cancellationTransport
        )
        let task = Task {
            try await cancellationLoader.image(
                loadRequest
            )
        }
        await cancellationTransport.waitUntilStarted()

        task.cancel()
        await cancellationTransport
            .waitUntilCancelled()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(
            await cancellationLoader.inFlightCount
                == 0
        )
        #expect(
            await cancellationLoader.cacheEntryCount
                == 0
        )
    }

    @Test("Rejects requests from another account")
    func accountIsolation() async throws {
        let transport =
            ControlledMarkdownImageTransport(
                result: .success(
                    response(
                        data: pngData,
                        contentType: "image/png"
                    )
                )
            )
        let loader = try makeLoader(
            transport: transport
        )
        let otherHost = try GitLabHost(
            "https://other.example.com"
        )
        let otherAccountRequest =
            GitLabMarkdownImageLoadRequest(
                accountID: GitLabAccountID(
                    host: otherHost,
                    userID: 2
                ),
                url: URL(
                    string:
                        "https://gitlab.example.com/uploads/image.png"
                )!,
                targetPixelWidth: 300
            )

        await #expect(
            throws:
                GitLabMarkdownImageError
                    .accountMismatch
        ) {
            try await loader.image(
                otherAccountRequest
            )
        }
        #expect(await transport.callCount == 0)
    }

    @Test("Normalizes render widths into bounded cache buckets")
    func targetWidthNormalization() {
        #expect(
            request(targetPixelWidth: 1)
                .targetPixelWidth == 128
        )
        #expect(
            request(targetPixelWidth: 129)
                .targetPixelWidth == 192
        )
        #expect(
            request(targetPixelWidth: 2_049)
                .targetPixelWidth == 2_048
        )
    }

    private var pngData: Data {
        Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
                + "AAAAC0lEQVR42mP8/x8AAusB9Wl2VQAAAABJRU5ErkJggg=="
        )!
    }

    private func makeLoader(
        transport:
            any GitLabMarkdownImageTransport,
        maximumImageCount: Int = 24,
        maximumDecodedCost: Int =
            24 * 1_024 * 1_024,
        maximumDownloadByteCount: Int =
            5 * 1_024 * 1_024,
        persistentResponseCache:
            (any GitLabResponseCaching)? = nil,
        persistentCachePolicy:
            GitLabResponseCachePolicy? = nil,
        currentDate:
            @escaping @Sendable () -> Date = Date.init
    ) throws -> GitLabMarkdownImageLoader {
        let host = try GitLabHost(
            "https://gitlab.example.com"
        )
        return GitLabMarkdownImageLoader(
            accountID: GitLabAccountID(
                host: host,
                userID: 1
            ),
            requestPolicy:
                GitLabMarkdownImageRequestPolicy(
                    host: host,
                    authorization:
                        .personalAccessToken(
                            "pat-secret"
                        )
                ),
            transport: transport,
            persistentResponseCache:
                persistentResponseCache,
            persistentCachePolicy:
                persistentCachePolicy,
            persistentCacheVariant: "test-image",
            maximumImageCount:
                maximumImageCount,
            maximumDecodedCost:
                maximumDecodedCost,
            maximumDownloadByteCount:
                maximumDownloadByteCount,
            currentDate: currentDate
        )
    }

    private func request(
        url: String =
            "https://gitlab.example.com/uploads/image.png",
        targetPixelWidth: Int = 300
    ) -> GitLabMarkdownImageLoadRequest {
        let host = try! GitLabHost(
            "https://gitlab.example.com"
        )
        return GitLabMarkdownImageLoadRequest(
            accountID: GitLabAccountID(
                host: host,
                userID: 1
            ),
            url: URL(string: url)!,
            targetPixelWidth: targetPixelWidth
        )
    }

    private func response(
        data: Data,
        contentType: String,
        contentLength: String? = nil
    ) -> GitLabMarkdownImageHTTPResponse {
        var headers = [
            "Content-Type": contentType,
        ]
        if let contentLength {
            headers["Content-Length"] =
                contentLength
        }
        return GitLabMarkdownImageHTTPResponse(
            data: data,
            response: HTTPURLResponse(
                url: URL(
                    string:
                        "https://gitlab.example.com/uploads/image.png"
                )!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: headers
            )!
        )
    }
}

private actor ControlledMarkdownImageTransport:
    GitLabMarkdownImageTransport
{
    private(set) var callCount = 0
    private let result:
        Result<
            GitLabMarkdownImageHTTPResponse,
            any Error
        >

    init(
        result:
            Result<
                GitLabMarkdownImageHTTPResponse,
                any Error
            >
    ) {
        self.result = result
    }

    func data(
        for request: URLRequest,
        maximumByteCount: Int
    ) async throws -> GitLabMarkdownImageHTTPResponse {
        callCount += 1
        return try result.get()
    }
}

private actor GatedMarkdownImageTransport:
    GitLabMarkdownImageTransport
{
    private(set) var callCount = 0
    private let response:
        GitLabMarkdownImageHTTPResponse
    private var didStart = false
    private var wasCancelled = false
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var finishContinuation:
        CheckedContinuation<Void, Never>?
    private var cancellationWaiters:
        [CheckedContinuation<Void, Never>] = []

    init(
        response: GitLabMarkdownImageHTTPResponse
    ) {
        self.response = response
    }

    func data(
        for request: URLRequest,
        maximumByteCount: Int
    ) async throws -> GitLabMarkdownImageHTTPResponse {
        callCount += 1
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        try await withTaskCancellationHandler {
            await withCheckedContinuation {
                finishContinuation = $0
            }
            try Task.checkCancellation()
        } onCancel: {
            Task {
                await self.recordCancellation()
            }
        }
        return response
    }

    func waitUntilStarted() async {
        guard !didStart else {
            return
        }
        await withCheckedContinuation {
            startWaiters.append($0)
        }
    }

    func finish() {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func waitUntilCancelled() async {
        guard !wasCancelled else {
            return
        }
        await withCheckedContinuation {
            cancellationWaiters.append($0)
        }
    }

    private func recordCancellation() {
        wasCancelled = true
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        waiters.forEach { $0.resume() }
        finish()
    }
}
