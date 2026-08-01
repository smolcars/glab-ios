import CoreGraphics
import Foundation
import ImageIO

nonisolated enum GitLabMarkdownImageError:
    Error,
    Equatable,
    Sendable,
    LocalizedError
{
    case unavailable
    case accountMismatch
    case invalidURL
    case invalidResponse
    case unsuccessfulResponse
    case invalidContentType
    case byteLimitExceeded
    case invalidImage
    case pixelLimitExceeded
    case networkFailure

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Image loading is unavailable."
        case .accountMismatch:
            "This image belongs to another GitLab account."
        case .invalidURL:
            "This image URL is not safe to load."
        case .invalidResponse:
            "The image server returned an invalid response."
        case .unsuccessfulResponse:
            "The image server could not return this image."
        case .invalidContentType:
            "The response was not an image."
        case .byteLimitExceeded:
            "This image is larger than the 5 MB limit."
        case .invalidImage:
            "The downloaded image could not be decoded."
        case .pixelLimitExceeded:
            "This image exceeds the safe dimension limit."
        case .networkFailure:
            "The image could not be downloaded."
        }
    }
}

nonisolated struct GitLabMarkdownImageRequestPolicy:
    Sendable
{
    private let host: GitLabHost
    private let authorization: GitLabAuthorization

    init(
        host: GitLabHost,
        authorization: GitLabAuthorization
    ) {
        self.host = host
        self.authorization = authorization
    }

    func request(
        for url: URL
    ) -> URLRequest? {
        guard Self.isSafeImageURL(url) else {
            return nil
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = GitLabHTTPMethod.get.rawValue
        request.setValue(
            "image/*",
            forHTTPHeaderField: "Accept"
        )
        if matchesGitLabOrigin(url) {
            authorization.apply(to: &request)
        }
        return request
    }

    func redirectedRequest(
        to url: URL
    ) -> URLRequest? {
        request(for: url)
    }

    private func matchesGitLabOrigin(
        _ url: URL
    ) -> Bool {
        guard
            let candidate = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            let expected = URLComponents(
                url: host.siteURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return false
        }

        return
            candidate.scheme?.lowercased() == "https"
            && candidate.host?.lowercased()
                == expected.host?.lowercased()
            && Self.effectivePort(candidate)
                == Self.effectivePort(expected)
    }

    private static func isSafeImageURL(
        _ url: URL
    ) -> Bool {
        guard
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            components.scheme?.lowercased() == "https",
            let host = components.host,
            !host.isEmpty,
            components.user == nil,
            components.password == nil
        else {
            return false
        }
        return true
    }

    private static func effectivePort(
        _ components: URLComponents
    ) -> Int {
        components.port ?? 443
    }
}

nonisolated struct GitLabMarkdownImageHTTPResponse:
    Sendable
{
    let data: Data
    let response: HTTPURLResponse
}

nonisolated protocol GitLabMarkdownImageTransport:
    Sendable
{
    func data(
        for request: URLRequest,
        maximumByteCount: Int
    ) async throws -> GitLabMarkdownImageHTTPResponse
}

nonisolated final class
    GitLabMarkdownImageRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    private let requestPolicy:
        GitLabMarkdownImageRequestPolicy

    init(
        requestPolicy:
            GitLabMarkdownImageRequestPolicy
    ) {
        self.requestPolicy = requestPolicy
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response:
            HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler:
            @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url else {
            completionHandler(nil)
            return
        }
        completionHandler(
            requestPolicy.redirectedRequest(to: url)
        )
    }
}

nonisolated struct
    URLSessionGitLabMarkdownImageTransport:
    GitLabMarkdownImageTransport
{
    private let session: URLSession
    private let requestPolicy:
        GitLabMarkdownImageRequestPolicy

    init(
        requestPolicy:
            GitLabMarkdownImageRequestPolicy
    ) {
        let configuration =
            URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy =
            .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false

        session = URLSession(
            configuration: configuration
        )
        self.requestPolicy = requestPolicy
    }

    func data(
        for request: URLRequest,
        maximumByteCount: Int
    ) async throws -> GitLabMarkdownImageHTTPResponse {
        let delegate =
            GitLabMarkdownImageRedirectDelegate(
                requestPolicy: requestPolicy
            )
        let (bytes, response) = try await session.bytes(
            for: request,
            delegate: delegate
        )
        guard
            let httpResponse =
                response as? HTTPURLResponse
        else {
            throw GitLabMarkdownImageError
                .invalidResponse
        }
        if
            httpResponse.expectedContentLength
                > Int64(maximumByteCount)
        {
            throw GitLabMarkdownImageError
                .byteLimitExceeded
        }

        var data = Data()
        if
            httpResponse.expectedContentLength > 0,
            httpResponse.expectedContentLength
                <= Int64(maximumByteCount)
        {
            data.reserveCapacity(
                Int(
                    httpResponse
                        .expectedContentLength
                )
            )
        }

        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumByteCount else {
                throw GitLabMarkdownImageError
                    .byteLimitExceeded
            }
            data.append(byte)
        }

        return GitLabMarkdownImageHTTPResponse(
            data: data,
            response: httpResponse
        )
    }
}

nonisolated struct GitLabMarkdownDecodedImage:
    @unchecked Sendable
{
    let cgImage: CGImage
    let pixelWidth: Int
    let pixelHeight: Int
    let decodedCost: Int

    init(cgImage: CGImage) {
        self.cgImage = cgImage
        pixelWidth = cgImage.width
        pixelHeight = cgImage.height
        let (cost, overflow) =
            cgImage.bytesPerRow
            .multipliedReportingOverflow(
                by: cgImage.height
            )
        decodedCost = overflow ? Int.max : cost
    }
}

nonisolated enum GitLabMarkdownImageDecoder {
    @concurrent
    static func decode(
        _ data: Data,
        targetPixelWidth: Int,
        maximumPixelCount: Int
    ) async throws -> GitLabMarkdownDecodedImage {
        try Task.checkCancellation()
        guard
            let source =
                CGImageSourceCreateWithData(
                    data as CFData,
                    [
                        kCGImageSourceShouldCache:
                            false,
                    ] as CFDictionary
                ),
            CGImageSourceGetCount(source) > 0,
            let properties =
                CGImageSourceCopyPropertiesAtIndex(
                    source,
                    0,
                    [
                        kCGImageSourceShouldCache:
                            false,
                    ] as CFDictionary
                ) as? [CFString: Any],
            let width =
                (properties[
                    kCGImagePropertyPixelWidth
                ] as? NSNumber)?.intValue,
            let height =
                (properties[
                    kCGImagePropertyPixelHeight
                ] as? NSNumber)?.intValue
        else {
            throw GitLabMarkdownImageError
                .invalidImage
        }

        guard
            hasValidPixelDimensions(
                width: width,
                height: height,
                maximumPixelCount:
                    maximumPixelCount
            )
        else {
            throw GitLabMarkdownImageError
                .pixelLimitExceeded
        }

        try Task.checkCancellation()
        let boundedTargetWidth = min(
            2_048,
            max(128, targetPixelWidth)
        )
        let maximumThumbnailDimension = min(
            max(width, height),
            height > width
                ? boundedTargetWidth * 2
                : boundedTargetWidth
        )
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways:
                true,
            kCGImageSourceCreateThumbnailWithTransform:
                true,
            kCGImageSourceShouldCacheImmediately:
                true,
            kCGImageSourceThumbnailMaxPixelSize:
                maximumThumbnailDimension,
        ]
        guard
            let cgImage =
                CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    options as CFDictionary
                )
        else {
            throw GitLabMarkdownImageError
                .invalidImage
        }
        try Task.checkCancellation()
        return GitLabMarkdownDecodedImage(
            cgImage: cgImage
        )
    }

    static func hasValidPixelDimensions(
        width: Int,
        height: Int,
        maximumPixelCount: Int
    ) -> Bool {
        guard
            width > 0,
            height > 0,
            maximumPixelCount > 0
        else {
            return false
        }

        let (pixelCount, overflow) =
            width.multipliedReportingOverflow(
                by: height
            )
        return
            !overflow
            && pixelCount <= maximumPixelCount
    }
}

nonisolated struct GitLabMarkdownImageLoadRequest:
    Equatable,
    Hashable,
    Sendable
{
    let accountID: GitLabAccountID
    let url: URL
    let targetPixelWidth: Int

    init(
        accountID: GitLabAccountID,
        url: URL,
        targetPixelWidth: Int
    ) {
        self.accountID = accountID
        self.url = url
        self.targetPixelWidth =
            Self.normalizedTargetPixelWidth(
                targetPixelWidth
            )
    }

    static func normalizedTargetPixelWidth(
        _ value: Int
    ) -> Int {
        let bounded = min(
            2_048,
            max(128, value)
        )
        return ((bounded + 63) / 64) * 64
    }
}

nonisolated protocol GitLabMarkdownImageLoading:
    Sendable
{
    func image(
        _ request:
            GitLabMarkdownImageLoadRequest
    ) async throws -> GitLabMarkdownDecodedImage
}

actor UnavailableGitLabMarkdownImageLoader:
    GitLabMarkdownImageLoading
{
    func image(
        _ request:
            GitLabMarkdownImageLoadRequest
    ) async throws -> GitLabMarkdownDecodedImage {
        throw GitLabMarkdownImageError.unavailable
    }
}

actor GitLabMarkdownImageLoader:
    GitLabMarkdownImageLoading
{
    typealias Decoder =
        @Sendable (
            Data,
            Int,
            Int
        ) async throws -> GitLabMarkdownDecodedImage

    private struct CacheKey:
        Equatable,
        Hashable,
        Sendable
    {
        let accountID: GitLabAccountID
        let url: URL
        let targetPixelWidth: Int
    }

    private struct CacheEntry {
        let image: GitLabMarkdownDecodedImage
        let decodedCost: Int
        var lastAccess: UInt64
    }

    private struct InFlightLoad {
        let identifier: UInt64
        let task:
            Task<
                GitLabMarkdownDecodedImage,
                any Error
            >
        var waiters: Set<UUID>
    }

    private let accountID: GitLabAccountID
    private let requestPolicy:
        GitLabMarkdownImageRequestPolicy
    private let transport:
        any GitLabMarkdownImageTransport
    private let persistentResponseCache:
        (any GitLabResponseCaching)?
    private let persistentCachePolicy:
        GitLabResponseCachePolicy?
    private let persistentCacheVariant: String?
    private let currentDate:
        @Sendable () -> Date
    private let maximumImageCount: Int
    private let maximumDecodedCost: Int
    private let maximumDownloadByteCount: Int
    private let maximumPixelCount: Int
    private let decoder: Decoder
    private var cache:
        [CacheKey: CacheEntry] = [:]
    private var inFlight:
        [CacheKey: InFlightLoad] = [:]
    private var accessCounter: UInt64 = 0
    private var loadCounter: UInt64 = 0

    init(
        accountID: GitLabAccountID,
        requestPolicy:
            GitLabMarkdownImageRequestPolicy,
        transport:
            any GitLabMarkdownImageTransport,
        persistentResponseCache:
            (any GitLabResponseCaching)? = nil,
        persistentCachePolicy:
            GitLabResponseCachePolicy? = nil,
        persistentCacheVariant: String? = nil,
        maximumImageCount: Int = 24,
        maximumDecodedCost: Int =
            24 * 1_024 * 1_024,
        maximumDownloadByteCount: Int =
            5 * 1_024 * 1_024,
        maximumPixelCount: Int = 16_000_000,
        currentDate:
            @escaping @Sendable () -> Date = Date.init,
        decoder: @escaping Decoder =
            GitLabMarkdownImageDecoder.decode
    ) {
        precondition(maximumImageCount > 0)
        precondition(maximumDecodedCost > 0)
        precondition(maximumDownloadByteCount > 0)
        precondition(maximumPixelCount > 0)
        self.accountID = accountID
        self.requestPolicy = requestPolicy
        self.transport = transport
        self.persistentResponseCache =
            persistentResponseCache
        self.persistentCachePolicy =
            persistentCachePolicy
        self.persistentCacheVariant =
            persistentCacheVariant
        self.maximumImageCount =
            maximumImageCount
        self.maximumDecodedCost =
            maximumDecodedCost
        self.maximumDownloadByteCount =
            maximumDownloadByteCount
        self.maximumPixelCount =
            maximumPixelCount
        self.currentDate = currentDate
        self.decoder = decoder
    }

    func image(
        _ request:
            GitLabMarkdownImageLoadRequest
    ) async throws -> GitLabMarkdownDecodedImage {
        try Task.checkCancellation()
        guard request.accountID == accountID else {
            throw GitLabMarkdownImageError
                .accountMismatch
        }
        let key = CacheKey(
            accountID: request.accountID,
            url: request.url,
            targetPixelWidth:
                request.targetPixelWidth
        )

        if var cached = cache[key] {
            cached.lastAccess = nextAccess()
            cache[key] = cached
            return cached.image
        }

        let waiterID = UUID()
        let load = try registerLoad(
            for: key,
            waiterID: waiterID
        )

        return try await withTaskCancellationHandler {
            do {
                let image = try await load.task.value
                try Task.checkCancellation()
                completeLoad(
                    image,
                    key: key,
                    loadID: load.identifier
                )
                return image
            } catch {
                cancelWaiter(
                    waiterID,
                    key: key,
                    loadID: load.identifier
                )
                if Task.isCancelled {
                    throw CancellationError()
                }
                throw error
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(
                    waiterID,
                    key: key,
                    loadID:
                        load.identifier
                )
            }
        }
    }

    var cacheEntryCount: Int {
        cache.count
    }

    var cacheDecodedCost: Int {
        cache.values.reduce(0) {
            let (sum, overflow) =
                $0.addingReportingOverflow(
                    $1.decodedCost
                )
            return overflow ? Int.max : sum
        }
    }

    var inFlightCount: Int {
        inFlight.count
    }

    private func registerLoad(
        for key: CacheKey,
        waiterID: UUID
    ) throws -> InFlightLoad {
        if var existing = inFlight[key] {
            existing.waiters.insert(waiterID)
            inFlight[key] = existing
            return existing
        }

        guard
            let request =
                requestPolicy.request(
                    for: key.url
                )
        else {
            throw GitLabMarkdownImageError
                .invalidURL
        }

        loadCounter &+= 1
        let load = InFlightLoad(
            identifier: loadCounter,
            task: Task {
                try await Self.load(
                    request: request,
                    targetPixelWidth:
                        key.targetPixelWidth,
                    maximumDownloadByteCount:
                        maximumDownloadByteCount,
                    maximumPixelCount:
                        maximumPixelCount,
                    transport: transport,
                    persistentResponseCache:
                        persistentResponseCache,
                    persistentCacheKey:
                        persistentCacheKey(
                            for: key.url
                        ),
                    persistentCachePolicy:
                        persistentCachePolicy,
                    currentDate: currentDate,
                    decoder: decoder
                )
            },
            waiters: [waiterID]
        )
        inFlight[key] = load
        return load
    }

    private static func load(
        request originalRequest: URLRequest,
        targetPixelWidth: Int,
        maximumDownloadByteCount: Int,
        maximumPixelCount: Int,
        transport:
            any GitLabMarkdownImageTransport,
        persistentResponseCache:
            (any GitLabResponseCaching)?,
        persistentCacheKey:
            GitLabResponseCacheKey?,
        persistentCachePolicy:
            GitLabResponseCachePolicy?,
        currentDate:
            @escaping @Sendable () -> Date,
        decoder: @escaping Decoder
    ) async throws -> GitLabMarkdownDecodedImage {
        var request = originalRequest
        var cached: GitLabCachedResponse?
        if
            let persistentResponseCache,
            let persistentCacheKey,
            let persistentCachePolicy,
            let stored = await persistentResponseCache
                .response(for: persistentCacheKey)
        {
            switch stored.freshness(
                at: currentDate(),
                policy: persistentCachePolicy
            ) {
            case .fresh:
                if let image = try? await decoder(
                    stored.body,
                    targetPixelWidth,
                    maximumPixelCount
                ) {
                    return image
                }
                await persistentResponseCache.remove(
                    for: persistentCacheKey
                )
            case .stale:
                cached = stored
                GitLabConditionalRequestValidators(
                    entityTag: stored.entityTag,
                    lastModified: stored.lastModified
                )
                .apply(to: &request)
            case .expired:
                await persistentResponseCache.remove(
                    for: persistentCacheKey
                )
            }
        }

        let response:
            GitLabMarkdownImageHTTPResponse
        do {
            response = try await transport.data(
                for: request,
                maximumByteCount:
                    maximumDownloadByteCount
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitLabMarkdownImageError {
            throw error
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            if
                let cached,
                let image = try? await decoder(
                    cached.body,
                    targetPixelWidth,
                    maximumPixelCount
                )
            {
                return image
            }
            throw GitLabMarkdownImageError
                .networkFailure
        }
        try Task.checkCancellation()

        let body: Data
        if response.response.statusCode == 304,
           let cached
        {
            body = cached.body
        } else {
            guard
                (200...299).contains(
                    response.response.statusCode
                )
            else {
                throw GitLabMarkdownImageError
                    .unsuccessfulResponse
            }
            guard
                let mimeType =
                    response.response.mimeType?
                        .lowercased(),
                mimeType.hasPrefix("image/")
            else {
                throw GitLabMarkdownImageError
                    .invalidContentType
            }
            guard
                response.data.count
                    <= maximumDownloadByteCount
            else {
                throw GitLabMarkdownImageError
                    .byteLimitExceeded
            }
            body = response.data
        }

        if
            let persistentResponseCache,
            let persistentCacheKey
        {
            let date = currentDate()
            try? await persistentResponseCache.store(
                GitLabCachedResponse(
                    body: body,
                    nextPageURL: nil,
                    totalCount: nil,
                    entityTag:
                        response.response.value(
                            forHTTPHeaderField: "ETag"
                        ) ?? cached?.entityTag,
                    lastModified:
                        response.response.value(
                            forHTTPHeaderField:
                                "Last-Modified"
                        ) ?? cached?.lastModified,
                    storedAt: date,
                    lastAccessedAt: date
                ),
                for: persistentCacheKey
            )
        }

        return try await decoder(
            body,
            targetPixelWidth,
            maximumPixelCount
        )
    }

    private func persistentCacheKey(
        for url: URL
    ) -> GitLabResponseCacheKey? {
        guard
            persistentResponseCache != nil,
            persistentCachePolicy != nil
        else {
            return nil
        }
        return GitLabResponseCacheKey(
            account: GitLabCacheAccount(
                host: accountID.host,
                userID: accountID.userID
            ),
            requestURL: url,
            variant: persistentCacheVariant
        )
    }

    private func completeLoad(
        _ image: GitLabMarkdownDecodedImage,
        key: CacheKey,
        loadID: UInt64
    ) {
        guard
            inFlight[key]?.identifier == loadID
        else {
            return
        }
        inFlight[key] = nil

        guard
            image.decodedCost
                <= maximumDecodedCost
        else {
            return
        }
        cache[key] = CacheEntry(
            image: image,
            decodedCost: image.decodedCost,
            lastAccess: nextAccess()
        )
        evictIfNeeded()
    }

    private func cancelWaiter(
        _ waiterID: UUID,
        key: CacheKey,
        loadID: UInt64
    ) {
        guard
            var load = inFlight[key],
            load.identifier == loadID,
            load.waiters.remove(waiterID) != nil
        else {
            return
        }

        guard load.waiters.isEmpty else {
            inFlight[key] = load
            return
        }
        inFlight[key] = nil
        load.task.cancel()
    }

    private func evictIfNeeded() {
        while
            cache.count > maximumImageCount
                || cacheDecodedCost
                    > maximumDecodedCost
        {
            guard
                let leastRecentlyUsed =
                    cache.min(
                        by: {
                            $0.value.lastAccess
                                < $1.value
                                    .lastAccess
                        }
                    )?.key
            else {
                return
            }
            cache[leastRecentlyUsed] = nil
        }
    }

    private func nextAccess() -> UInt64 {
        accessCounter &+= 1
        return accessCounter
    }

}
