import Foundation

nonisolated enum GitLabMarkdownMediaError:
    Error,
    Equatable,
    Sendable,
    LocalizedError
{
    case unavailable
    case accountMismatch
    case invalidURL
    case invalidContentType
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Media loading is unavailable."
        case .accountMismatch:
            "This media belongs to another GitLab account."
        case .invalidURL:
            "This media URL is not safe to load."
        case .invalidContentType:
            "The response was not the expected media type."
        case .downloadFailed:
            "The media could not be downloaded."
        }
    }
}

nonisolated struct GitLabMarkdownMediaLoadRequest:
    Equatable,
    Sendable
{
    let accountID: GitLabAccountID
    let urls: [URL]
    let kind: GitLabMarkdownMediaKind
    let preferredFileExtension: String?

    init(
        accountID: GitLabAccountID,
        urls: [URL],
        kind: GitLabMarkdownMediaKind,
        preferredFileExtension: String? = nil
    ) {
        self.accountID = accountID
        self.urls = urls
        self.kind = kind
        self.preferredFileExtension =
            kind.normalizedFileExtension(
                preferredFileExtension
            )
    }
}

nonisolated protocol GitLabMarkdownMediaLoading:
    Sendable
{
    func file(
        for request: GitLabMarkdownMediaLoadRequest
    ) async throws -> URL

    func removeFile(at url: URL) async
}

actor UnavailableGitLabMarkdownMediaLoader:
    GitLabMarkdownMediaLoading
{
    func file(
        for request: GitLabMarkdownMediaLoadRequest
    ) async throws -> URL {
        throw GitLabMarkdownMediaError.unavailable
    }

    func removeFile(at url: URL) async {}
}

actor GitLabMarkdownMediaLoader:
    GitLabMarkdownMediaLoading
{
    private let accountID: GitLabAccountID
    private let requestPolicy:
        GitLabMarkdownImageRequestPolicy
    private let downloader:
        any GitLabHTTPFileDownloading
    private let temporaryDirectory: URL
    private let maximumByteCount: Int

    init(
        accountID: GitLabAccountID,
        requestPolicy:
            GitLabMarkdownImageRequestPolicy,
        downloader:
            any GitLabHTTPFileDownloading =
                URLSessionGitLabHTTPFileDownloader(),
        temporaryDirectory: URL =
            FileManager.default.temporaryDirectory,
        maximumByteCount: Int =
            100 * 1_024 * 1_024
    ) {
        precondition(maximumByteCount > 0)
        self.accountID = accountID
        self.requestPolicy = requestPolicy
        self.downloader = downloader
        self.temporaryDirectory = temporaryDirectory
        self.maximumByteCount = maximumByteCount
    }

    func file(
        for request: GitLabMarkdownMediaLoadRequest
    ) async throws -> URL {
        try Task.checkCancellation()
        guard request.accountID == accountID else {
            throw GitLabMarkdownMediaError
                .accountMismatch
        }
        guard
            request.kind != .image,
            !request.urls.isEmpty
        else {
            throw GitLabMarkdownMediaError.invalidURL
        }

        var lastError: (any Error)?
        for url in request.urls {
            try Task.checkCancellation()
            guard
                let urlRequest = requestPolicy.request(
                    for: url,
                    accept: request.kind == .video
                        ? "video/*"
                        : "audio/*"
                )
            else {
                lastError = GitLabMarkdownMediaError
                    .invalidURL
                continue
            }

            do {
                let download = try await downloader.download(
                    for: urlRequest,
                    maximumByteCount: maximumByteCount,
                    temporaryDirectory: temporaryDirectory
                )
                do {
                    try validate(
                        download.response,
                        kind: request.kind
                    )
                    return try prepareForPlayback(
                        download.fileURL,
                        sourceURL: url,
                        preferredFileExtension:
                            request.preferredFileExtension,
                        kind: request.kind
                    )
                } catch {
                    try? FileManager.default.removeItem(
                        at: download.fileURL
                    )
                    throw error
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        if let error = lastError {
            throw error
        }
        throw GitLabMarkdownMediaError.downloadFailed
    }

    func removeFile(at url: URL) async {
        guard
            url.deletingLastPathComponent()
                .standardizedFileURL
                == temporaryDirectory.standardizedFileURL,
            url.lastPathComponent.hasPrefix(
                ".glab-media-"
            )
        else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    private func validate(
        _ response: HTTPURLResponse,
        kind: GitLabMarkdownMediaKind
    ) throws {
        guard let mimeType = response.mimeType?
            .lowercased()
        else {
            return
        }
        let expectedPrefix = kind == .video
            ? "video/"
            : "audio/"
        guard
            mimeType.hasPrefix(expectedPrefix)
                || mimeType == "application/octet-stream"
        else {
            throw GitLabMarkdownMediaError
                .invalidContentType
        }
    }

    private func prepareForPlayback(
        _ downloadedURL: URL,
        sourceURL: URL,
        preferredFileExtension: String?,
        kind: GitLabMarkdownMediaKind
    ) throws -> URL {
        var filename = ".glab-media-"
            + UUID().uuidString
        let fileExtension = preferredFileExtension
            ?? kind.normalizedFileExtension(
                sourceURL.pathExtension
            )
        if let fileExtension {
            filename += "." + fileExtension
        }
        let destination = temporaryDirectory
            .appending(
                path: filename,
                directoryHint: .notDirectory
            )
        do {
            try FileManager.default.moveItem(
                at: downloadedURL,
                to: destination
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var protectedURL = destination
            try protectedURL.setResourceValues(values)
            return destination
        } catch {
            try? FileManager.default.removeItem(
                at: downloadedURL
            )
            try? FileManager.default.removeItem(
                at: destination
            )
            throw GitLabMarkdownMediaError.downloadFailed
        }
    }
}
