import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab job trace loader")
struct LiveGitLabJobTraceLoaderTests {
    @Test("Downloads, indexes, commits, and restores one trace")
    func loadsAndCachesTrace() async throws {
        try await Self.withStore {
            store,
            rootDirectory in
            let raw = TraceRawDownloader(
                behavior:
                    .data(
                        Data(
                            "first\nerror: failed\n"
                            .utf8
                        )
                    )
            )
            let loader =
                LiveGitLabJobTraceLoader(
                    session: raw,
                    store: store
                )
            let key = try Self.traceKey()

            let descriptor =
                try await loader
                .loadTrace(for: key)

            #expect(descriptor.key == key)
            #expect(descriptor.lineCount == 2)
            #expect(
                descriptor
                    .firstLikelyFailure
                    == GitLabJobTraceFailureLocation(
                        lineIndex: 1,
                        category: .error
                    )
            )
            #expect(
                try Data(
                    contentsOf:
                        descriptor
                        .traceFileURL
                )
                    == Data(
                        "first\nerror: failed\n"
                        .utf8
                    )
            )
            #expect(
                await loader
                    .cachedDescriptor(
                        for: key
                    ) == descriptor
            )
            #expect(
                Self.recursiveURLs(
                    below: rootDirectory
                )
                .allSatisfy {
                    !$0.lastPathComponent
                        .hasPrefix(".import-")
                }
            )
        }
    }

    @Test("Maps a missing trace and discards its partial workspace")
    func mapsNotFoundAndDiscardsPartial()
        async throws
    {
        try await Self.withStore {
            store,
            rootDirectory in
            let raw = TraceRawDownloader(
                behavior:
                    .partialFailure(
                        .session(
                            .api(.notFound)
                        )
                    )
            )
            let loader =
                LiveGitLabJobTraceLoader(
                    session: raw,
                    store: store
                )

            await #expect(
                throws:
                    GitLabJobTraceLoadError
                    .noTrace
            ) {
                try await loader.loadTrace(
                    for: try Self.traceKey()
                )
            }

            #expect(
                Self.recursiveURLs(
                    below: rootDirectory
                )
                .allSatisfy {
                    !$0.lastPathComponent
                        .hasPrefix(".import-")
                        && $0.lastPathComponent
                            != "partial.raw"
                }
            )
        }
    }

    @Test("Maps the indexed line bound and keeps no descriptor")
    func mapsLineLimit() async throws {
        try await Self.withStore {
            store,
            _ in
            let key = try Self.traceKey()
            let loader =
                LiveGitLabJobTraceLoader(
                    session:
                        TraceRawDownloader(
                            behavior:
                                .data(
                                    Data(
                                        "one\ntwo\n"
                                        .utf8
                                    )
                                )
                        ),
                    store: store,
                    indexer:
                        GitLabJobTraceIndexer(
                            maximumLineCount: 1
                        )
                )

            await #expect(
                throws:
                    GitLabJobTraceLoadError
                    .tooLarge
            ) {
                try await loader
                    .loadTrace(for: key)
            }
            #expect(
                await store.descriptor(
                    for: key
                ) == nil
            )
        }
    }

    @Test("Cancellation reaches the downloader and discards partial data")
    func cancellationCleansUp() async throws {
        try await Self.withStore {
            store,
            rootDirectory in
            let raw = TraceRawDownloader(
                behavior: .gated
            )
            let loader =
                LiveGitLabJobTraceLoader(
                    session: raw,
                    store: store
                )
            let task = Task {
                try await loader
                    .loadTrace(
                        for: try Self.traceKey()
                    )
            }
            await raw.waitUntilStarted()

            task.cancel()

            await #expect(
                throws:
                    GitLabJobTraceLoadError
                    .cancelled
            ) {
                try await task.value
            }
            #expect(
                await raw
                    .cancellationCount == 1
            )
            #expect(
                Self.recursiveURLs(
                    below: rootDirectory
                )
                .allSatisfy {
                    !$0.lastPathComponent
                        .hasPrefix(".import-")
                        && $0.lastPathComponent
                            != "partial.raw"
                }
            )
        }
    }
}

private extension LiveGitLabJobTraceLoaderTests {
    static func withStore(
        _ operation:
            (
                FileGitLabJobTraceStore,
                URL
            ) async throws -> Void
    ) async throws {
        let rootDirectory =
            FileManager.default
            .temporaryDirectory
            .appending(
                path:
                    "glab-live-trace-loader-tests-"
                    + UUID().uuidString,
                directoryHint: .isDirectory
            )
        defer {
            try? FileManager.default
                .removeItem(
                    at: rootDirectory
                )
        }
        let store =
            FileGitLabJobTraceStore(
                rootDirectory:
                    rootDirectory
            )
        try await operation(
            store,
            rootDirectory
        )
    }

    static func traceKey()
        throws -> GitLabJobTraceKey
    {
        GitLabJobTraceKey(
            accountID:
                GitLabAccountID(
                    host:
                        try GitLabHost(
                            "gitlab.example.com"
                        ),
                    userID: 7
                ),
            route:
                try #require(
                    GitLabJobTraceRoute(
                        projectID: 42,
                        jobID: 800
                    )
                )
        )
    }

    static func recursiveURLs(
        below rootDirectory: URL
    ) -> [URL] {
        guard
            let enumerator =
                FileManager.default
                .enumerator(
                    at: rootDirectory,
                    includingPropertiesForKeys:
                        nil
                )
        else {
            return []
        }
        return enumerator.compactMap {
            $0 as? URL
        }
    }
}

private actor TraceRawDownloader:
    GitLabRawFileSessionDownloading
{
    enum Behavior: Sendable {
        case data(Data)
        case partialFailure(
            GitLabRawFileSessionError
        )
        case gated
    }

    private let behavior: Behavior
    private var starts = 0
    private var cancellations = 0
    private var gateWaiters: [
        UUID:
            CheckedContinuation<
                Void,
                any Error
            >
    ] = [:]

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    var cancellationCount: Int {
        cancellations
    }

    func waitUntilStarted() async {
        while starts == 0 {
            await Task.yield()
        }
    }

    func downloadRawFile(
        _ endpoint: GitLabRawAPIRequest,
        maximumByteCount: Int,
        temporaryDirectory: URL
    ) async throws(GitLabRawFileSessionError)
        -> GitLabHTTPDownloadedFile
    {
        starts += 1
        let fileURL =
            temporaryDirectory
            .appending(
                path: "partial.raw",
                directoryHint:
                    .notDirectory
            )

        switch behavior {
        case let .data(data):
            do {
                try data.write(to: fileURL)
                return try downloadedFile(
                    at: fileURL,
                    byteCount: data.count
                )
            } catch {
                throw .storageFailure
            }
        case let .partialFailure(error):
            do {
                try Data("partial".utf8)
                    .write(to: fileURL)
            } catch {
                throw .storageFailure
            }
            throw error
        case .gated:
            do {
                try Data("partial".utf8)
                    .write(to: fileURL)
                try await waitForCancellation()
                throw CancellationError()
            } catch is CancellationError {
                cancellations += 1
                throw .session(
                    .api(.cancelled)
                )
            } catch {
                throw .storageFailure
            }
        }
    }

    private func waitForCancellation()
        async throws
    {
        let id = UUID()
        try await
            withTaskCancellationHandler {
                try await
                    withCheckedThrowingContinuation {
                        (
                            continuation:
                                CheckedContinuation<
                                    Void,
                                    any Error
                                >
                        ) in
                        if Task.isCancelled {
                            continuation
                                .resume(
                                    throwing:
                                        CancellationError()
                                )
                        } else {
                            gateWaiters[id] =
                                continuation
                        }
                    }
            } onCancel: {
                Task {
                    await self.cancelWaiter(
                        id
                    )
                }
            }
    }

    private func cancelWaiter(_ id: UUID) {
        gateWaiters
            .removeValue(forKey: id)?
            .resume(
                throwing:
                    CancellationError()
            )
    }

    private func downloadedFile(
        at fileURL: URL,
        byteCount: Int
    ) throws -> GitLabHTTPDownloadedFile {
        guard
            let url = URL(
                string:
                    "https://gitlab.example.com/api/v4/projects/42/jobs/800/trace"
            ),
            let response =
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )
        else {
            throw GitLabRawFileSessionError
                .storageFailure
        }
        return GitLabHTTPDownloadedFile(
            fileURL: fileURL,
            response: response,
            byteCount: byteCount
        )
    }
}
