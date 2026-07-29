import Foundation
import Testing
@testable import Glab

@Suite("GitLab job trace viewport")
@MainActor
struct GitLabJobTraceViewportTests {
    @Test("Projects a centered bounded window at every document edge")
    func projectsBoundedWindow() {
        #expect(
            GitLabJobTraceViewportWindow.range(
                around: 0,
                lineCount: 10_000
            ) == 0..<512
        )
        #expect(
            GitLabJobTraceViewportWindow.range(
                around: 5_000,
                lineCount: 10_000
            ) == 4_744..<5_256
        )
        #expect(
            GitLabJobTraceViewportWindow.range(
                around: 9_999,
                lineCount: 10_000
            ) == 9_488..<10_000
        )
        #expect(
            GitLabJobTraceViewportWindow.range(
                around: -1,
                lineCount: 10_000
            ).isEmpty
        )
        #expect(
            GitLabJobTraceViewportWindow.range(
                around: 10_000,
                lineCount: 10_000
            ).isEmpty
        )
    }

    @Test("Loads one bounded window and exposes only its lines")
    func loadsBoundedWindow() async throws {
        let reader = ViewportReader()
        let document =
            GitLabJobTraceDocument(
                descriptor:
                    try descriptor(
                        lineCount: 10_000
                    ),
                reader: reader
            )
        let viewport =
            GitLabJobTraceViewport(
                document: document
            )

        await viewport.load(around: 5_000)

        #expect(viewport.loadedRange == 4_744..<5_256)
        #expect(viewport.loadedLineCount == 512)
        #expect(viewport.line(at: 5_000)?.text == "line 5000")
        #expect(viewport.line(at: 4_743) == nil)
        #expect(
            await reader.ranges
                == [4_744..<5_256]
        )
    }

    @Test("Visible requests inside an in-flight window coalesce")
    func coalescesContainedRequests() async throws {
        let reader = ViewportReader(
            isGated: true
        )
        let document =
            GitLabJobTraceDocument(
                descriptor:
                    try descriptor(
                        lineCount: 10_000
                    ),
                reader: reader
            )
        let viewport =
            GitLabJobTraceViewport(
                document: document
            )

        let first = Task {
            await viewport.load(
                around: 5_000
            )
        }
        await reader.waitUntilReadStarts()
        let second = Task {
            await viewport.load(
                around: 5_010
            )
        }
        await Task.yield()

        #expect(await reader.callCount == 1)

        await reader.release()
        await first.value
        await second.value

        #expect(viewport.loadedLineCount == 512)
        #expect(await reader.callCount == 1)
    }

    @Test("A superseding window cannot publish stale lines")
    func suppressesSupersededWindow() async throws {
        let reader = ViewportReader(
            isGated: true
        )
        let document =
            GitLabJobTraceDocument(
                descriptor:
                    try descriptor(
                        lineCount: 10_000
                    ),
                reader: reader
            )
        let viewport =
            GitLabJobTraceViewport(
                document: document
            )

        let first = Task {
            await viewport.load(
                around: 100
            )
        }
        await reader.waitUntilReadStarts()
        let second = Task {
            await viewport.load(
                around: 9_000
            )
        }
        for _ in 0..<100
        where await reader.callCount < 2 {
            await Task.yield()
        }
        #expect(await reader.callCount == 2)

        await reader.release()
        await first.value
        await second.value

        #expect(viewport.loadedRange == 8_744..<9_256)
        #expect(viewport.line(at: 9_000) != nil)
        #expect(viewport.line(at: 100) == nil)
    }

    @Test("Cancellation clears work without publishing an error")
    func cancellationIsSilent() async throws {
        let reader = ViewportReader(
            isGated: true
        )
        let document =
            GitLabJobTraceDocument(
                descriptor:
                    try descriptor(
                        lineCount: 1_000
                    ),
                reader: reader
            )
        let viewport =
            GitLabJobTraceViewport(
                document: document
            )

        let load = Task {
            await viewport.load(
                around: 500
            )
        }
        await reader.waitUntilReadStarts()
        viewport.cancel()
        await reader.release()
        await load.value

        #expect(viewport.loadedRange.isEmpty)
        #expect(viewport.loadedLineCount == 0)
        #expect(viewport.error == nil)
    }

    @Test("Layout metrics stay bounded for pathological lines")
    func layoutMetricsAreBounded() {
        let ordinary =
            GitLabJobTraceLayoutMetrics
            .contentWidth(
                renderedByteCount: 120,
                glyphWidth: 8,
                lineCount: 50_000
            )
        let pathological =
            GitLabJobTraceLayoutMetrics
            .contentWidth(
                renderedByteCount:
                    GitLabJobTraceIndexer
                    .maximumRenderedLineByteCount
                    * 2,
                glyphWidth: 8,
                lineCount: 50_000
            )

        #expect(ordinary > 960)
        #expect(
            pathological
                == GitLabJobTraceLayoutMetrics
                .maximumContentWidth
        )
        #expect(
            GitLabJobTraceLayoutMetrics
                .contentWidth(
                    renderedByteCount:
                        GitLabJobTraceIndexer
                        .maximumRenderedLineByteCount,
                    glyphWidth: 24,
                    lineCount: 5_000_000
                )
                == GitLabJobTraceLayoutMetrics
                .maximumContentWidth
        )
    }

    @Test("VoiceOver labels include state without retaining pathological text")
    func accessibilityLabelsAreCapped() {
        let line = GitLabJobTraceLine(
            index: 41,
            text:
                String(
                    repeating: "a",
                    count: 10_000
                ),
            rawByteCount: 12_000,
            isTruncated: true
        )

        let label =
            GitLabJobTraceAccessibility
            .label(for: line)

        #expect(label.hasPrefix("Line 42, "))
        #expect(label.hasSuffix(", truncated"))
        #expect(
            label.count
                <= GitLabJobTraceAccessibility
                .maximumLabelCharacterCount
                + 32
        )
    }

    private func descriptor(
        lineCount: Int
    ) throws -> GitLabJobTraceDescriptor {
        let accountID =
            GitLabAccountID(
                host:
                    try GitLabHost(
                        "gitlab.example.com"
                    ),
                userID: 7
            )
        let route = try #require(
            GitLabJobTraceRoute(
                projectID: 42,
                jobID: 800
            )
        )
        return GitLabJobTraceDescriptor(
            key:
                GitLabJobTraceKey(
                    accountID: accountID,
                    route: route
                ),
            traceFileURL:
                URL(
                    filePath:
                        "/tmp/viewport.raw"
                ),
            indexFileURL:
                URL(
                    filePath:
                        "/tmp/viewport.idx"
                ),
            byteCount: lineCount * 8,
            lineCount: lineCount,
            storedAt:
                Date(
                    timeIntervalSince1970:
                        1_000
                ),
            rawContentDigest: "viewport",
            longLineCount: 0
        )
    }
}

private actor ViewportReader:
    GitLabJobTraceReading
{
    private let isGated: Bool
    private var isReleased = false
    private var continuations: [
        CheckedContinuation<Void, Never>
    ] = []
    private var requestedRanges: [
        Range<Int>
    ] = []

    init(isGated: Bool = false) {
        self.isGated = isGated
    }

    var ranges: [Range<Int>] {
        requestedRanges
    }

    var callCount: Int {
        requestedRanges.count
    }

    func lines(
        in range: Range<Int>,
        descriptor:
            GitLabJobTraceDescriptor,
        maximumLineByteCount: Int
    ) async throws
        -> [GitLabJobTraceLine]
    {
        requestedRanges.append(range)
        if isGated, !isReleased {
            await withCheckedContinuation {
                continuation in
                continuations.append(
                    continuation
                )
            }
        }
        try Task.checkCancellation()
        return range.map { index in
            GitLabJobTraceLine(
                index: index,
                text: "line \(index)",
                rawByteCount: 8,
                isTruncated: false
            )
        }
    }

    func search(
        _ query: String,
        descriptor:
            GitLabJobTraceDescriptor,
        maximumLineByteCount: Int,
        maximumResultCount: Int
    ) async throws
        -> GitLabJobTraceSearchResult
    {
        .empty
    }

    func waitUntilReadStarts() async {
        await waitUntilCallCount(1)
    }

    func waitUntilCallCount(
        _ expected: Int
    ) async {
        while requestedRanges.count
            < expected
        {
            await Task.yield()
        }
    }

    func release() {
        isReleased = true
        for continuation in continuations {
            continuation.resume()
        }
        continuations.removeAll()
    }
}
