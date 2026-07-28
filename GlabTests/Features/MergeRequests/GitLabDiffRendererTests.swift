import Foundation
import Testing
@testable import Glab

@Suite("GitLab diff renderer cache")
struct GitLabDiffRendererTests {
    @Test("Cache key isolates every private revision identity field")
    func cacheKeyIsolation() throws {
        let request = try makeRequest(
            source: "First",
            headSHA: "head-a"
        )
        let same = GitLabDiffCacheKey(
            request: request,
            parserVersion: 1
        )

        #expect(
            same
                == GitLabDiffCacheKey(
                    request: request,
                    parserVersion: 1
                )
        )
        #expect(
            same
                != GitLabDiffCacheKey(
                    request: try makeRequest(
                        source: "First",
                        userID: 2,
                        headSHA: "head-a"
                    ),
                    parserVersion: 1
                )
        )
        #expect(
            same
                != GitLabDiffCacheKey(
                    request: try makeRequest(
                        source: "First",
                        projectID: 11,
                        headSHA: "head-a"
                    ),
                    parserVersion: 1
                )
        )
        #expect(
            same
                != GitLabDiffCacheKey(
                    request: try makeRequest(
                        source: "First",
                        mergeRequestIID: 8,
                        headSHA: "head-a"
                    ),
                    parserVersion: 1
                )
        )
        #expect(
            same
                != GitLabDiffCacheKey(
                    request: try makeRequest(
                        source: "First",
                        headSHA: "head-b"
                    ),
                    parserVersion: 1
                )
        )
        #expect(
            same
                != GitLabDiffCacheKey(
                    request: try makeRequest(
                        source: "First",
                        headSHA: "head-a",
                        newPath: "Sources/Other.swift"
                    ),
                    parserVersion: 1
                )
        )
        #expect(
            same
                != GitLabDiffCacheKey(
                    request: try makeRequest(
                        source: "Second",
                        headSHA: "head-a"
                    ),
                    parserVersion: 1
                )
        )
        #expect(
            same
                != GitLabDiffCacheKey(
                    request: request,
                    parserVersion: 2
                )
        )
        #expect(
            same.description
                == "GitLabDiffCacheKey(<redacted>)"
        )
        #expect(!same.description.contains(request.source))
        #expect(!same.description.contains(request.headSHA))
    }

    @Test("Returns a cached document without parsing twice")
    func cacheHit() async throws {
        let parser = CountingDiffParser()
        let renderer = GitLabDiffRenderer(
            parser: parser.parse
        )
        let request = try makeRequest(
            source: "cached",
            headSHA: "head"
        )

        let first = try await renderer.render(request)
        let second = try await renderer.render(request)

        #expect(first == second)
        #expect(await parser.callCount == 1)
        #expect(await renderer.cacheEntryCount == 1)
    }

    @Test("Promotes cache hits and evicts the least recently used file")
    func leastRecentlyUsedEviction() async throws {
        let parser = CountingDiffParser()
        let renderer = GitLabDiffRenderer(
            maximumDocumentCount: 2,
            maximumEstimatedCost: 100_000,
            parser: parser.parse
        )
        let first = try makeRequest(
            source: "first",
            headSHA: "head",
            newPath: "first.swift"
        )
        let second = try makeRequest(
            source: "second",
            headSHA: "head",
            newPath: "second.swift"
        )
        let third = try makeRequest(
            source: "third",
            headSHA: "head",
            newPath: "third.swift"
        )

        _ = try await renderer.render(first)
        _ = try await renderer.render(second)
        _ = try await renderer.render(first)
        _ = try await renderer.render(third)
        _ = try await renderer.render(second)

        #expect(await parser.callCount == 4)
        #expect(await renderer.cacheEntryCount == 2)
    }

    @Test("Enforces estimated-cost bounds and bypasses oversized files")
    func estimatedCostLimit() async throws {
        let parser = CountingDiffParser()
        let renderer = GitLabDiffRenderer(
            maximumDocumentCount: 10,
            maximumEstimatedCost: 500,
            parser: parser.parse
        )
        let first = try makeRequest(
            source: String(repeating: "a", count: 100),
            headSHA: "head",
            newPath: "first.swift"
        )
        let second = try makeRequest(
            source: String(repeating: "b", count: 100),
            headSHA: "head",
            newPath: "second.swift"
        )
        let oversized = try makeRequest(
            source: String(repeating: "c", count: 600),
            headSHA: "head",
            newPath: "large.swift"
        )

        _ = try await renderer.render(first)
        _ = try await renderer.render(second)
        _ = try await renderer.render(oversized)
        _ = try await renderer.render(oversized)

        #expect(await renderer.cacheEstimatedCost <= 500)
        #expect(await renderer.cacheEntryCount == 2)
        #expect(await parser.callCount == 4)
    }

    @Test("A newer head immediately replaces the same file's stale head")
    func staleHeadReplacement() async throws {
        let parser = CountingDiffParser()
        let renderer = GitLabDiffRenderer(
            parser: parser.parse
        )
        let old = try makeRequest(
            source: "old",
            headSHA: "head-a"
        )
        let new = try makeRequest(
            source: "new",
            headSHA: "head-b"
        )

        _ = try await renderer.render(old)
        _ = try await renderer.render(new)
        _ = try await renderer.render(old)

        #expect(await parser.callCount == 3)
        #expect(await renderer.cacheEntryCount == 1)
    }

    @Test("Identical in-flight parses share one task")
    func inFlightCoalescing() async throws {
        let parser = GatedDiffParser()
        let renderer = GitLabDiffRenderer(
            parser: parser.parse
        )
        let request = try makeRequest(
            source: "coalesced",
            headSHA: "head"
        )

        async let first = renderer.render(request)
        async let second = renderer.render(request)
        await parser.waitUntilStarted()

        #expect(await parser.callCount == 1)
        #expect(await renderer.inFlightCount == 1)
        await parser.finish()

        let values = try await [first, second]
        #expect(values[0] == values[1])
        #expect(await renderer.cacheEntryCount == 1)
        #expect(await renderer.inFlightCount == 0)
    }

    @Test("Cancelling one waiter preserves a shared parse")
    func oneWaiterCancellation() async throws {
        let parser = GatedDiffParser()
        let renderer = GitLabDiffRenderer(
            parser: parser.parse
        )
        let request = try makeRequest(
            source: "shared",
            headSHA: "head"
        )
        let first = Task {
            try await renderer.render(request)
        }
        let second = Task {
            try await renderer.render(request)
        }
        await parser.waitUntilStarted()

        first.cancel()
        await parser.finish()

        await #expect(throws: CancellationError.self) {
            try await first.value
        }
        _ = try await second.value
        #expect(await parser.cancellationCount == 0)
        #expect(await renderer.cacheEntryCount == 1)
    }

    @Test("Cancelling the last waiter cancels its parse")
    func lastWaiterCancellation() async throws {
        let parser = GatedDiffParser()
        let renderer = GitLabDiffRenderer(
            parser: parser.parse
        )
        let request = try makeRequest(
            source: "cancelled",
            headSHA: "head"
        )
        let task = Task {
            try await renderer.render(request)
        }
        await parser.waitUntilStarted()

        task.cancel()
        await parser.waitUntilCancelled()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await renderer.inFlightCount == 0)
        #expect(await renderer.cacheEntryCount == 0)
    }

    @Test("An older completion cannot replace a newer head")
    func outOfOrderHeadCompletion() async throws {
        let parser = OutOfOrderDiffParser()
        let renderer = GitLabDiffRenderer(
            parser: parser.parse
        )
        let old = try makeRequest(
            source: "old",
            headSHA: "head-a"
        )
        let new = try makeRequest(
            source: "new",
            headSHA: "head-b"
        )

        let oldTask = Task {
            try await renderer.render(old)
        }
        await parser.waitUntilStarted("old")
        let newTask = Task {
            try await renderer.render(new)
        }
        await parser.waitUntilStarted("new")

        await parser.finish("new")
        _ = try await newTask.value
        await parser.finish("old")
        _ = try await oldTask.value
        _ = try await renderer.render(new)

        #expect(await parser.callCount == 2)
        #expect(await renderer.cacheEntryCount == 1)
    }

    private func makeRequest(
        source: String,
        userID: Int = 1,
        projectID: Int = 10,
        mergeRequestIID: Int = 7,
        headSHA: String,
        oldPath: String = "Sources/File.swift",
        newPath: String = "Sources/File.swift"
    ) throws -> GitLabDiffRequest {
        let host = try GitLabHost(
            "https://gitlab.example.com"
        )
        return GitLabDiffRequest(
            accountID: GitLabAccountID(
                host: host,
                userID: userID
            ),
            route: GitLabMergeRequestRoute(
                projectID: projectID,
                mergeRequestIID: mergeRequestIID
            ),
            headSHA: headSHA,
            oldPath: oldPath,
            newPath: newPath,
            source: source
        )
    }
}

private actor CountingDiffParser {
    private(set) var callCount = 0

    func parse(
        _ source: String
    ) async throws -> GitLabParsedDiffDocument {
        callCount += 1
        return testDocument(source)
    }
}

private actor GatedDiffParser {
    private(set) var callCount = 0
    private(set) var cancellationCount = 0
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var finishContinuation:
        CheckedContinuation<Void, Never>?
    private var cancellationWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var didStart = false
    private var wasCancelled = false

    func parse(
        _ source: String
    ) async throws -> GitLabParsedDiffDocument {
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
        return testDocument(source)
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
        cancellationCount += 1
        wasCancelled = true
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        waiters.forEach { $0.resume() }
        finish()
    }
}

private actor OutOfOrderDiffParser {
    private(set) var callCount = 0
    private var startedSources: Set<String> = []
    private var startWaiters:
        [
            String:
                [CheckedContinuation<Void, Never>]
        ] = [:]
    private var finishContinuations:
        [
            String:
                CheckedContinuation<Void, Never>
        ] = [:]

    func parse(
        _ source: String
    ) async throws -> GitLabParsedDiffDocument {
        callCount += 1
        startedSources.insert(source)
        let waiters =
            startWaiters.removeValue(
                forKey: source
            )
            ?? []
        waiters.forEach { $0.resume() }
        await withCheckedContinuation {
            finishContinuations[source] = $0
        }
        return testDocument(source)
    }

    func waitUntilStarted(
        _ source: String
    ) async {
        guard !startedSources.contains(source) else {
            return
        }
        await withCheckedContinuation {
            startWaiters[source, default: []]
                .append($0)
        }
    }

    func finish(
        _ source: String
    ) {
        finishContinuations
            .removeValue(forKey: source)?
            .resume()
    }
}

private nonisolated func testDocument(
    _ source: String
) -> GitLabParsedDiffDocument {
    GitLabParsedDiffDocument(
        items: [.fileMetadata(source)],
        hunks: [],
        lineCount: 1,
        estimatedCacheCost: source.utf8.count,
        maximumRenderedLineLength: source.count
    )
}
