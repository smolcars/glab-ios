import Foundation

nonisolated protocol GitLabHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

nonisolated struct URLSessionGitLabHTTPTransport: GitLabHTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

extension URLSessionGitLabHTTPTransport:
    GitLabHTTPFileDownloading
{
    func download(
        for request: URLRequest,
        maximumByteCount: Int,
        temporaryDirectory: URL
    ) async throws -> GitLabHTTPDownloadedFile {
        try await
            URLSessionGitLabHTTPFileDownloader()
            .download(
                for: request,
                maximumByteCount:
                    maximumByteCount,
                temporaryDirectory:
                    temporaryDirectory
            )
    }
}
