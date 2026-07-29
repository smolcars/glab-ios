import Foundation
import Testing
@testable import Glab

@Suite("GitLab job trace document")
struct GitLabJobTraceDocumentTests {
    @Test("Reads only sanitized bounded visible lines")
    func readsVisibleWindow() async throws {
        var trace =
            Data("plain\r\n".utf8)
        trace.append(
            contentsOf:
                "\u{1B}[31mred\u{1B}[0m\n"
                .utf8
        )
        trace.append(contentsOf: [
            0x66,
            0x80,
            0x6F,
        ])

        try await withTraceDescriptor(
            trace: trace
        ) { descriptor in
            let document =
                GitLabJobTraceDocument(
                    descriptor: descriptor
                )
            let lines =
                try await document.lines(
                    in: 0..<3
                )

            #expect(
                lines.map(\.text)
                    == [
                        "plain",
                        "red",
                        "f�o",
                    ]
            )
            #expect(
                lines.map(\.displayNumber)
                    == [1, 2, 3]
            )
            #expect(
                lines.map(\.rawByteCount)
                    == [5, 12, 3]
            )
            #expect(
                lines.allSatisfy {
                    !$0.isTruncated
                }
            )
        }
    }

    @Test("Truncates a very long line at the byte budget")
    func truncatesLongLine() async throws {
        let byteCount =
            GitLabJobTraceIndexer
            .maximumRenderedLineByteCount
            + 1
        let trace =
            Data(
                repeating: 0x61,
                count: byteCount
            )

        try await withTraceDescriptor(
            trace: trace
        ) { descriptor in
            let document =
                GitLabJobTraceDocument(
                    descriptor: descriptor
                )
            let line = try #require(
                await document
                    .lines(in: 0..<1)
                    .first
            )

            #expect(
                line.rawByteCount
                    == byteCount
            )
            #expect(line.isTruncated)
            #expect(
                line.text.utf8.count
                    == GitLabJobTraceIndexer
                    .maximumRenderedLineByteCount
            )
        }
    }

    @Test("Rejects out-of-range visible windows")
    func rejectsInvalidWindow() async throws {
        try await withTraceDescriptor(
            trace: Data("one\n".utf8)
        ) { descriptor in
            let document =
                GitLabJobTraceDocument(
                    descriptor: descriptor
                )

            await #expect(
                throws:
                    GitLabJobTraceDocumentError
                    .invalidRange
            ) {
                try await document.lines(
                    in: 0..<2
                )
            }
        }
    }

    @Test("Rejects a corrupt line index after cache publication")
    func rejectsCorruptPublishedIndex() async throws {
        try await withTraceDescriptor(
            trace: Data("one\ntwo".utf8)
        ) { descriptor in
            try encodedOffsets([0, 2])
                .write(
                    to:
                        descriptor
                        .indexFileURL
                )
            let document =
                GitLabJobTraceDocument(
                    descriptor: descriptor
                )

            await #expect(
                throws:
                    GitLabJobTraceDocumentError
                    .invalidFile
            ) {
                try await document.lines(
                    in: 0..<2
                )
            }
        }
    }

    @Test("Rejects a visible window above the hard line bound")
    func rejectsOversizedWindow() async throws {
        let maximum =
            GitLabJobTraceDocument
            .maximumVisibleWindowLineCount
        let document =
            GitLabJobTraceDocument(
                descriptor:
                    try testDescriptor(
                        lineCount:
                            maximum + 1
                    ),
                reader:
                    ImmediateJobTraceReader()
            )

        await #expect(
            throws:
                GitLabJobTraceDocumentError
                .invalidRange
        ) {
            try await document.lines(
                in: 0..<(maximum + 1)
            )
        }
    }

    @Test("Coalesces concurrent contained windows")
    func coalescesVisibleWindows() async throws {
        let reader =
            GatedJobTraceReader()
        let descriptor =
            try testDescriptor(
                lineCount: 4
            )
        let document =
            GitLabJobTraceDocument(
                descriptor: descriptor,
                reader: reader
            )
        let first = Task {
            try await document.lines(
                in: 0..<4
            )
        }
        await reader
            .waitUntilLineReadStarts()
        let second = Task {
            try await document.lines(
                in: 1..<3
            )
        }

        await reader.releaseLineRead()

        #expect(
            try await first.value
                .map(\.index)
                == [0, 1, 2, 3]
        )
        #expect(
            try await second.value
                .map(\.index)
                == [1, 2]
        )
        #expect(
            await reader.lineReadCount
                == 1
        )
    }

    @Test("Partially overlapping windows do not reread shared lines")
    func coalescesPartialOverlap() async throws {
        let reader =
            GatedJobTraceReader()
        let document =
            GitLabJobTraceDocument(
                descriptor:
                    try testDescriptor(
                        lineCount: 6
                    ),
                reader: reader
            )
        let first = Task {
            try await document.lines(
                in: 0..<4
            )
        }
        await reader
            .waitUntilLineReadStarts()
        let second = Task {
            try await document.lines(
                in: 2..<6
            )
        }

        await reader.releaseLineRead()

        #expect(
            try await first.value
                .map(\.index)
                == [0, 1, 2, 3]
        )
        #expect(
            try await second.value
                .map(\.index)
                == [2, 3, 4, 5]
        )
        #expect(
            await reader.requestedLineRanges
                == [0..<4, 4..<6]
        )
    }

    @Test("Bounds the decoded line LRU by count and bytes")
    func boundsVisibleCache() async throws {
        let reader =
            ImmediateJobTraceReader()
        let descriptor =
            try testDescriptor(
                lineCount: 6
            )
        let document =
            GitLabJobTraceDocument(
                descriptor: descriptor,
                reader: reader,
                maximumCachedLineCount: 2,
                maximumCachedByteCount: 18
            )

        _ = try await document.lines(
            in: 0..<2
        )
        _ = try await document.lines(
            in: 2..<4
        )
        _ = try await document.lines(
            in: 4..<6
        )
        let metrics =
            await document.cacheMetrics()

        #expect(metrics.lineCount <= 2)
        #expect(metrics.byteCount <= 18)
    }

    @Test("Search is case and diacritic insensitive plain text")
    func searchesFileBackedLines() async throws {
        let trace =
            Data(
                (
                    "Érror: first\n"
                        + "ok\n"
                        + "ERROR: second\n"
                        + "error: third"
                ).utf8
            )

        try await withTraceDescriptor(
            trace: trace
        ) { descriptor in
            let document =
                GitLabJobTraceDocument(
                    descriptor: descriptor
                )
            let result =
                try await document.search(
                    "error:"
                )

            #expect(
                result.lineIndexes
                    == [0, 2, 3]
            )
            #expect(
                result.selectedMatchPosition
                    == nil
            )
            #expect(
                !result.hasAdditionalMatches
            )
        }
    }

    @Test("Search matches text separated by terminal controls")
    func searchesAcrossTerminalControls() async throws {
        let trace =
            Data(
                "er\u{1B}[31mror:\u{1B}[0m failed"
                    .utf8
            )

        try await withTraceDescriptor(
            trace: trace
        ) { descriptor in
            let result =
                try await
                    GitLabJobTraceDocument(
                        descriptor: descriptor
                    )
                    .search("error:")

            #expect(
                result.lineIndexes == [0]
            )
        }
    }

    @Test("Search caps retained results and reports more")
    func capsSearchResults() async throws {
        let trace =
            Data(
                Array(
                    repeating: "match\n",
                    count: 2_002
                )
                .joined()
                .utf8
            )

        try await withTraceDescriptor(
            trace: trace
        ) { descriptor in
            let document =
                GitLabJobTraceDocument(
                    descriptor: descriptor
                )
            let result =
                try await document.search(
                    "match"
                )

            #expect(
                result.lineIndexes.count
                    == GitLabJobTraceDocument
                    .maximumSearchResultCount
            )
            #expect(
                result.lineIndexes.first
                    == 0
            )
            #expect(
                result.lineIndexes.last
                    == 1_999
            )
            #expect(
                result.hasAdditionalMatches
            )
        }
    }

    @Test("Rejects search text above the UTF-8 byte bound")
    func rejectsOversizedSearch() async throws {
        let document =
            GitLabJobTraceDocument(
                descriptor:
                    try testDescriptor(
                        lineCount: 1
                    ),
                reader:
                    ImmediateJobTraceReader()
            )
        let query =
            String(
                repeating: "é",
                count: 129
            )

        await #expect(
            throws:
                GitLabJobTraceDocumentError
                .invalidRange
        ) {
            try await document.search(query)
        }
    }

    @Test("A new search cancels stale publication")
    func cancelsStaleSearch() async throws {
        let reader =
            GatedJobTraceReader()
        let document =
            GitLabJobTraceDocument(
                descriptor:
                    try testDescriptor(
                        lineCount: 3
                    ),
                reader: reader
            )
        let stale = Task {
            try await document.search(
                "old"
            )
        }
        await reader
            .waitUntilSearchStarts()

        let current = Task {
            try await document.search(
                "new"
            )
        }
        await reader
            .waitUntilSearchCount(2)
        await reader.releaseSearches()

        await #expect(
            throws: CancellationError.self
        ) {
            try await stale.value
        }
        #expect(
            try await current.value
                .lineIndexes
                == [2]
        )
    }

    @Test("Empty search cancels work and clears results")
    func emptySearchCancelsWork() async throws {
        let reader =
            GatedJobTraceReader()
        let document =
            GitLabJobTraceDocument(
                descriptor:
                    try testDescriptor(
                        lineCount: 3
                    ),
                reader: reader
            )
        let stale = Task {
            try await document.search(
                "old"
            )
        }
        await reader
            .waitUntilSearchStarts()

        let cleared =
            try await document.search(
                "   "
            )
        await reader.releaseSearches()

        #expect(cleared.lineIndexes.isEmpty)
        #expect(
            cleared.selectedMatchPosition
                == nil
        )
        await #expect(
            throws: CancellationError.self
        ) {
            try await stale.value
        }
    }

    @Test("Invalidation cancels visible work")
    func invalidationCancelsWindow()
        async throws
    {
        let reader =
            GatedJobTraceReader()
        let document =
            GitLabJobTraceDocument(
                descriptor:
                    try testDescriptor(
                        lineCount: 3
                    ),
                reader: reader
            )
        let task = Task {
            try await document.lines(
                in: 0..<3
            )
        }
        await reader
            .waitUntilLineReadStarts()

        await document.invalidate()
        await reader.releaseLineRead()

        await #expect(
            throws: CancellationError.self
        ) {
            try await task.value
        }
        #expect(
            await document
                .cacheMetrics()
                .lineCount
                == 0
        )
    }

    @Test("Rejects an incomplete reader window instead of retrying")
    func rejectsIncompleteReaderWindow()
        async throws
    {
        let document =
            GitLabJobTraceDocument(
                descriptor:
                    try testDescriptor(
                        lineCount: 2
                    ),
                reader:
                    IncompleteJobTraceReader()
            )

        await #expect(
            throws:
                GitLabJobTraceDocumentError
                .invalidFile
        ) {
            try await document.lines(
                in: 0..<2
            )
        }
    }
}

private actor GatedJobTraceReader:
    GitLabJobTraceReading
{
    private(set) var lineReadCount = 0
    private(set) var requestedLineRanges:
        [Range<Int>] = []
    private(set) var searchCount = 0
    private var lineReadStarted = false
    private var searchesReleased = false
    private var lineReadReleased = false
    private var lineStartWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var lineReleaseWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var searchCountWaiters:
        [(
            Int,
            CheckedContinuation<Void, Never>
        )] = []
    private var searchReleaseWaiters:
        [CheckedContinuation<Void, Never>] = []

    func lines(
        in range: Range<Int>,
        descriptor: GitLabJobTraceDescriptor,
        maximumLineByteCount: Int
    ) async throws -> [GitLabJobTraceLine] {
        lineReadCount += 1
        requestedLineRanges.append(range)
        lineReadStarted = true
        let waiters = lineStartWaiters
        lineStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        if !lineReadReleased {
            await withCheckedContinuation {
                lineReleaseWaiters
                    .append($0)
            }
        }
        try Task.checkCancellation()
        return range.map {
            GitLabJobTraceLine(
                index: $0,
                text: "line-\($0)",
                rawByteCount: 6,
                isTruncated: false
            )
        }
    }

    func search(
        _ query: String,
        descriptor: GitLabJobTraceDescriptor,
        maximumLineByteCount: Int,
        maximumResultCount: Int
    ) async throws
        -> GitLabJobTraceSearchResult
    {
        searchCount += 1
        let count = searchCount
        let ready =
            searchCountWaiters
            .filter { $0.0 <= count }
        searchCountWaiters.removeAll {
            $0.0 <= count
        }
        for waiter in ready {
            waiter.1.resume()
        }
        if !searchesReleased {
            await withCheckedContinuation {
                searchReleaseWaiters
                    .append($0)
            }
        }
        try Task.checkCancellation()
        return GitLabJobTraceSearchResult(
            lineIndexes:
                query == "new"
                ? [2]
                : [0],
            selectedMatchPosition: 0,
            hasAdditionalMatches: false
        )
    }

    func waitUntilLineReadStarts()
        async
    {
        guard !lineReadStarted else {
            return
        }
        await withCheckedContinuation {
            lineStartWaiters.append($0)
        }
    }

    func releaseLineRead() {
        lineReadReleased = true
        let waiters = lineReleaseWaiters
        lineReleaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilSearchStarts()
        async
    {
        await waitUntilSearchCount(1)
    }

    func waitUntilSearchCount(
        _ expected: Int
    ) async {
        guard searchCount >= expected else {
            await withCheckedContinuation {
                searchCountWaiters
                    .append(
                        (expected, $0)
                    )
            }
            return
        }
    }

    func releaseSearches() {
        searchesReleased = true
        let waiters = searchReleaseWaiters
        searchReleaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor ImmediateJobTraceReader:
    GitLabJobTraceReading
{
    func lines(
        in range: Range<Int>,
        descriptor: GitLabJobTraceDescriptor,
        maximumLineByteCount: Int
    ) -> [GitLabJobTraceLine] {
        range.map {
            GitLabJobTraceLine(
                index: $0,
                text: "line-\($0)",
                rawByteCount: 6,
                isTruncated: false
            )
        }
    }

    func search(
        _ query: String,
        descriptor: GitLabJobTraceDescriptor,
        maximumLineByteCount: Int,
        maximumResultCount: Int
    ) -> GitLabJobTraceSearchResult {
        GitLabJobTraceSearchResult(
            lineIndexes: [],
            selectedMatchPosition: nil,
            hasAdditionalMatches: false
        )
    }
}

private actor IncompleteJobTraceReader:
    GitLabJobTraceReading
{
    func lines(
        in range: Range<Int>,
        descriptor: GitLabJobTraceDescriptor,
        maximumLineByteCount: Int
    ) -> [GitLabJobTraceLine] {
        [
            GitLabJobTraceLine(
                index: range.lowerBound,
                text: "incomplete",
                rawByteCount: 10,
                isTruncated: false
            ),
        ]
    }

    func search(
        _ query: String,
        descriptor: GitLabJobTraceDescriptor,
        maximumLineByteCount: Int,
        maximumResultCount: Int
    ) -> GitLabJobTraceSearchResult {
        .empty
    }
}

private func withTraceDescriptor(
    trace: Data,
    operation: (
        GitLabJobTraceDescriptor
    ) async throws -> Void
) async throws {
    let directory =
        FileManager.default
        .temporaryDirectory
        .appending(
            path:
                "GlabTraceDocumentTests-"
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
        path: "trace.raw",
        directoryHint: .notDirectory
    )
    let indexURL = directory.appending(
        path: "lines.idx",
        directoryHint: .notDirectory
    )
    try trace.write(to: traceURL)
    try encodedLineOffsets(trace)
        .write(to: indexURL)
    let descriptor =
        try testDescriptor(
            traceFileURL: traceURL,
            indexFileURL: indexURL,
            byteCount: trace.count,
            lineCount:
                lineOffsets(trace).count
        )

    try await operation(descriptor)
}

private func testDescriptor(
    traceFileURL: URL =
        URL(filePath: "/trace.raw"),
    indexFileURL: URL =
        URL(filePath: "/lines.idx"),
    byteCount: Int = 12,
    lineCount: Int
) throws -> GitLabJobTraceDescriptor {
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
    return GitLabJobTraceDescriptor(
        key: GitLabJobTraceKey(
            accountID: accountID,
            route: route
        ),
        traceFileURL: traceFileURL,
        indexFileURL: indexFileURL,
        byteCount: byteCount,
        lineCount: lineCount,
        storedAt: Date(
            timeIntervalSince1970: 1_000
        ),
        rawContentDigest:
            String(repeating: "a", count: 64),
        longLineCount: 0
    )
}

private func encodedLineOffsets(
    _ data: Data
) -> Data {
    encodedOffsets(lineOffsets(data))
}

private func encodedOffsets(
    _ offsets: [UInt32]
) -> Data {
    var result = Data()
    for offset in offsets {
        var value = offset.littleEndian
        withUnsafeBytes(of: &value) {
            result.append(
                contentsOf: $0
            )
        }
    }
    return result
}

private func lineOffsets(
    _ data: Data
) -> [UInt32] {
    guard !data.isEmpty else {
        return []
    }
    var offsets: [UInt32] = [0]
    for (index, byte) in data.enumerated()
    where
        byte == 0x0A
            && index + 1 < data.count
    {
        offsets.append(
            UInt32(index + 1)
        )
    }
    return offsets
}
