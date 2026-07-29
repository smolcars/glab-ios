import CryptoKit
import Foundation
import Testing
@testable import Glab

@Suite("GitLab job trace indexer")
struct GitLabJobTraceIndexerTests {
    @Test(
        "Indexes empty, terminated, unterminated, CRLF, and empty lines",
        arguments: [
            TraceIndexFixture(
                bytes: Data(),
                offsets: []
            ),
            TraceIndexFixture(
                bytes: Data("one".utf8),
                offsets: [0]
            ),
            TraceIndexFixture(
                bytes: Data("one\n".utf8),
                offsets: [0]
            ),
            TraceIndexFixture(
                bytes:
                    Data("one\r\ntwo".utf8),
                offsets: [0, 5]
            ),
            TraceIndexFixture(
                bytes:
                    Data("\n\nthree\n".utf8),
                offsets: [0, 1, 2]
            ),
        ]
    )
    func indexesLineBoundaries(
        fixture: TraceIndexFixture
    ) async throws {
        try await withIndexWorkspace(
            trace: fixture.bytes
        ) { workspace, traceURL in
            let prepared =
                try await GitLabJobTraceIndexer()
                    .prepare(
                        traceFileURL: traceURL,
                        byteCount:
                            fixture.bytes.count,
                        in: workspace
                    )

            #expect(
                try decodeOffsets(
                    at:
                        prepared
                        .indexFileURL
                ) == fixture.offsets
            )
            #expect(
                prepared.lineCount
                    == fixture.offsets.count
            )
            #expect(
                prepared.rawContentDigest
                    == digest(fixture.bytes)
            )
            #expect(
                prepared.indexFormatVersion
                    == GitLabJobTraceIndexFormat
                    .currentVersion
            )
        }
    }

    @Test("Records long lines and the first likely failure")
    func recordsIndexFacts() async throws {
        var trace =
            Data(
                repeating: 0x78,
                count:
                    GitLabJobTraceIndexer
                    .maximumRenderedLineByteCount
                    + 1
            )
        trace.append(0x0A)
        trace.append(
            contentsOf:
                "\u{1B}[31mERROR:\u{1B}[0m failed build\n"
                .utf8
        )

        try await withIndexWorkspace(
            trace: trace
        ) { workspace, traceURL in
            let prepared =
                try await GitLabJobTraceIndexer()
                    .prepare(
                        traceFileURL: traceURL,
                        byteCount: trace.count,
                        in: workspace
                    )

            #expect(prepared.lineCount == 2)
            #expect(prepared.longLineCount == 1)
            #expect(
                prepared
                    .firstLikelyFailure
                    == GitLabJobTraceFailureLocation(
                        lineIndex: 1,
                        category: .error
                    )
            )
        }
    }

    @Test("Finds a failure marker separated by terminal controls")
    func recordsSanitizedFailureMarker() async throws {
        let trace =
            Data(
                "er\u{1B}[31mror:\u{1B}[0m failed"
                    .utf8
            )

        try await withIndexWorkspace(
            trace: trace
        ) { workspace, traceURL in
            let prepared =
                try await
                    GitLabJobTraceIndexer()
                    .prepare(
                        traceFileURL:
                            traceURL,
                        byteCount:
                            trace.count,
                        in: workspace
                    )

            #expect(
                prepared
                    .firstLikelyFailure
                    == GitLabJobTraceFailureLocation(
                        lineIndex: 0,
                        category: .error
                    )
            )
        }
    }

    @Test("Stops before exceeding the configured line limit")
    func rejectsTooManyLines() async throws {
        try await withIndexWorkspace(
            trace: Data("a\nb\nc".utf8)
        ) { workspace, traceURL in
            let indexer =
                GitLabJobTraceIndexer(
                    maximumLineCount: 2,
                    chunkByteCount: 2
                )

            await #expect(
                throws:
                    GitLabJobTraceIndexingError
                    .tooManyLines
            ) {
                try await indexer.prepare(
                    traceFileURL: traceURL,
                    byteCount: 5,
                    in: workspace
                )
            }
            let remainingIndexFiles =
                try indexFiles(
                    in:
                        workspace
                        .directoryURL
                )
            #expect(remainingIndexFiles.isEmpty)
        }
    }

    @Test("Cancellation removes the partial index")
    func cancellationRemovesPartialIndex()
        async throws
    {
        let trace =
            Data(
                repeating: 0x61,
                count: 128 * 1_024
            )
        let gate = TraceIndexChunkGate()

        try await withIndexWorkspace(
            trace: trace
        ) { workspace, traceURL in
            let indexer =
                GitLabJobTraceIndexer(
                    chunkByteCount: 1_024,
                    chunkCheckpoint: {
                        await gate.checkpoint()
                    }
                )
            let task = Task {
                try await indexer.prepare(
                    traceFileURL: traceURL,
                    byteCount: trace.count,
                    in: workspace
                )
            }

            await gate.waitUntilReached()
            task.cancel()
            await gate.open()

            await #expect(
                throws: CancellationError.self
            ) {
                try await task.value
            }
            let remainingIndexFiles =
                try indexFiles(
                    in:
                        workspace
                        .directoryURL
                )
            #expect(remainingIndexFiles.isEmpty)
        }
    }

    @Test("Creates a protected index excluded from backup")
    func protectsIndex() async throws {
        try await withIndexWorkspace(
            trace: Data("safe\n".utf8)
        ) { workspace, traceURL in
            let prepared =
                try await GitLabJobTraceIndexer()
                    .prepare(
                        traceFileURL: traceURL,
                        byteCount: 5,
                        in: workspace
                    )
            let attributes =
                try FileManager.default
                    .attributesOfItem(
                        atPath:
                            prepared
                            .indexFileURL
                            .path
                    )
            let values =
                try prepared.indexFileURL
                    .resourceValues(
                        forKeys: [
                            .isExcludedFromBackupKey,
                        ]
                    )

            let protection =
                attributes[.protectionKey]
                    as? FileProtectionType
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
            #expect(
                values.isExcludedFromBackup
                    == true
            )
        }
    }
}

struct TraceIndexFixture:
    CustomTestStringConvertible,
    Sendable
{
    let bytes: Data
    let offsets: [UInt32]

    var testDescription: String {
        "bytes=\(bytes.count), lines=\(offsets.count)"
    }
}

private actor TraceIndexChunkGate {
    private var reached = false
    private var isOpen = false
    private var reachedWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var openWaiters:
        [CheckedContinuation<Void, Never>] = []

    func checkpoint() async {
        reached = true
        let waiters = reachedWaiters
        reachedWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        guard !isOpen else {
            return
        }
        await withCheckedContinuation {
            openWaiters.append($0)
        }
    }

    func waitUntilReached() async {
        guard !reached else {
            return
        }
        await withCheckedContinuation {
            reachedWaiters.append($0)
        }
    }

    func open() {
        isOpen = true
        let waiters = openWaiters
        openWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private func withIndexWorkspace(
    trace: Data,
    operation: (
        GitLabJobTraceImportWorkspace,
        URL
    ) async throws -> Void
) async throws {
    let directory =
        FileManager.default
        .temporaryDirectory
        .appending(
            path:
                "GlabTraceIndexerTests-"
                + UUID().uuidString,
            directoryHint: .isDirectory
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer {
        try? FileManager.default
            .removeItem(at: directory)
    }
    let traceURL = directory.appending(
        path: "trace.download",
        directoryHint: .notDirectory
    )
    try trace.write(
        to: traceURL,
        options:
            .completeFileProtectionUntilFirstUserAuthentication
    )
    let accountID = GitLabAccountID(
        host: try GitLabHost(
            "https://gitlab.example.com"
        ),
        userID: 7
    )
    let route = try #require(
        GitLabJobTraceRoute(
            projectID: 42,
            jobID: 9
        )
    )
    let workspace =
        GitLabJobTraceImportWorkspace(
            key: GitLabJobTraceKey(
                accountID: accountID,
                route: route
            ),
            directoryURL: directory,
            identifier: UUID()
        )

    try await operation(
        workspace,
        traceURL
    )
}

private func decodeOffsets(
    at fileURL: URL
) throws -> [UInt32] {
    let data = try Data(
        contentsOf: fileURL
    )
    guard
        data.count
            % MemoryLayout<UInt32>.size
            == 0
    else {
        return []
    }
    var offsets: [UInt32] = []
    offsets.reserveCapacity(
        data.count
            / MemoryLayout<UInt32>.size
    )
    var index = 0
    while index < data.count {
        let first = UInt32(data[index])
        let second =
            UInt32(data[index + 1]) << 8
        let third =
            UInt32(data[index + 2]) << 16
        let fourth =
            UInt32(data[index + 3]) << 24
        offsets.append(
            first | second | third | fourth
        )
        index += MemoryLayout<UInt32>.size
    }
    return offsets
}

private func indexFiles(
    in directory: URL
) throws -> [URL] {
    try FileManager.default
        .contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.lastPathComponent
                .hasPrefix(
                    ".glab-index-"
                )
        }
}

private func digest(
    _ data: Data
) -> String {
    SHA256.hash(data: data)
        .map {
            String(format: "%02x", $0)
        }
        .joined()
}
