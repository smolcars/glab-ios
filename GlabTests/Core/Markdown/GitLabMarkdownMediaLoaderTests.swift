import Foundation
import Testing
@testable import Glab

@Suite("GitLab Markdown media loader")
struct GitLabMarkdownMediaLoaderTests {
    @Test("Authenticates project media, falls back, and removes playback files")
    func authenticatedFallbackAndCleanup() async throws {
        let directory = FileManager.default
            .temporaryDirectory
            .appending(
                path: "markdown-media-tests-" + UUID().uuidString,
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }

        let host = try GitLabHost(
            "https://gitlab.example.com"
        )
        let accountID = GitLabAccountID(
            host: host,
            userID: 7
        )
        let downloader = RecordingMediaDownloader()
        let loader = GitLabMarkdownMediaLoader(
            accountID: accountID,
            requestPolicy:
                GitLabMarkdownImageRequestPolicy(
                    host: host,
                    authorization:
                        .personalAccessToken(
                            "private-token"
                        )
                ),
            downloader: downloader,
            temporaryDirectory: directory,
            maximumByteCount: 1_024
        )
        let primary = URL(
            string:
                "https://gitlab.example.com/-/project/10/uploads/abc/demo.mp4"
        )!
        let fallback = URL(
            string:
                "https://gitlab.example.com/group/project/uploads/abc/demo.mp4"
        )!

        let fileURL = try await loader.file(
            for: GitLabMarkdownMediaLoadRequest(
                accountID: accountID,
                urls: [primary, fallback],
                kind: .video
            )
        )

        #expect(fileURL.pathExtension == "mp4")
        #expect(FileManager.default.fileExists(
            atPath: fileURL.path
        ))
        let requests = await downloader.recordedRequests()
        #expect(requests.map(\.url) == [primary, fallback])
        #expect(
            requests.allSatisfy {
                $0.value(
                    forHTTPHeaderField: "PRIVATE-TOKEN"
                ) == "private-token"
            }
        )
        #expect(
            requests.allSatisfy {
                $0.value(
                    forHTTPHeaderField: "Accept"
                ) == "video/*"
            }
        )

        await loader.removeFile(at: fileURL)
        #expect(!FileManager.default.fileExists(
            atPath: fileURL.path
        ))

        let repositoryRawURL = URL(
            string:
                "https://gitlab.example.com/api/v4/projects/10/repository/files/media%2Fdemo.mp4/raw?ref=main"
        )!
        let repositoryFileURL = try await loader.file(
            for: GitLabMarkdownMediaLoadRequest(
                accountID: accountID,
                urls: [repositoryRawURL],
                kind: .video,
                preferredFileExtension: "mp4"
            )
        )

        #expect(repositoryFileURL.pathExtension == "mp4")
        await loader.removeFile(at: repositoryFileURL)
        #expect(!FileManager.default.fileExists(
            atPath: repositoryFileURL.path
        ))
    }
}

private actor RecordingMediaDownloader:
    GitLabHTTPFileDownloading
{
    private var requests: [URLRequest] = []

    func download(
        for request: URLRequest,
        maximumByteCount: Int,
        temporaryDirectory: URL
    ) async throws -> GitLabHTTPDownloadedFile {
        requests.append(request)
        guard let url = request.url else {
            throw GitLabHTTPFileDownloadError
                .invalidConfiguration
        }
        if url.path.hasPrefix("/-/project/") {
            throw GitLabHTTPFileDownloadError
                .unsuccessfulStatus(404)
        }

        let data = Data("video".utf8)
        let fileURL = temporaryDirectory
            .appending(
                path: ".stub-" + UUID().uuidString,
                directoryHint: .notDirectory
            )
        try data.write(to: fileURL)
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "video/mp4",
                ]
            )
        )
        return GitLabHTTPDownloadedFile(
            fileURL: fileURL,
            response: response,
            byteCount: data.count
        )
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}
