import Foundation
import Testing
@testable import Glab

@Suite("GitLab Markdown renderer cache")
struct GitLabMarkdownRendererTests {
    @Test("Cache key isolates account, resource, content, and version")
    func cacheKeyIsolation() throws {
        let request = try makeRequest(
            source: "First",
            userID: 1,
            issueIID: 1
        )
        let same = GitLabMarkdownCacheKey(
            request: request,
            rendererVersion: 1
        )

        #expect(
            same
                == GitLabMarkdownCacheKey(
                    request: request,
                    rendererVersion: 1
                )
        )
        #expect(
            same
                != GitLabMarkdownCacheKey(
                    request: try makeRequest(
                        source: "First",
                        userID: 2,
                        issueIID: 1
                    ),
                    rendererVersion: 1
                )
        )
        #expect(
            same
                != GitLabMarkdownCacheKey(
                    request: try makeRequest(
                        source: "First",
                        userID: 1,
                        issueIID: 2
                    ),
                    rendererVersion: 1
                )
        )
        #expect(
            same
                != GitLabMarkdownCacheKey(
                    request: try makeRequest(
                        source: "Second",
                        userID: 1,
                        issueIID: 1
                    ),
                    rendererVersion: 1
                )
        )
        #expect(
            same
                != GitLabMarkdownCacheKey(
                    request: request,
                    rendererVersion: 2
                )
        )
        #expect(same.description == "GitLabMarkdownCacheKey(<redacted>)")
        #expect(
            same.description.contains(request.source)
                == false
        )
    }

    @Test("Returns a cached document without parsing twice")
    func cacheHit() async throws {
        let parser = CountingMarkdownParser()
        let renderer = GitLabMarkdownRenderer(
            parser: parser.parse
        )
        let request = try makeRequest(source: "# Cached")

        let first = try await renderer.render(request)
        let second = try await renderer.render(request)

        #expect(first == second)
        #expect(await parser.callCount == 1)
        #expect(await renderer.cacheEntryCount == 1)
    }

    @Test("Promotes a hit and evicts the least recently used entry")
    func leastRecentlyUsedEviction() async throws {
        let parser = CountingMarkdownParser()
        let renderer = GitLabMarkdownRenderer(
            maximumDocumentCount: 2,
            maximumSourceCost: 10_000,
            parser: parser.parse
        )
        let first = try makeRequest(
            source: "First",
            issueIID: 1
        )
        let second = try makeRequest(
            source: "Second",
            issueIID: 2
        )
        let third = try makeRequest(
            source: "Third",
            issueIID: 3
        )

        _ = try await renderer.render(first)
        _ = try await renderer.render(second)
        _ = try await renderer.render(first)
        _ = try await renderer.render(third)
        _ = try await renderer.render(second)

        #expect(await parser.callCount == 4)
        #expect(await renderer.cacheEntryCount == 2)
    }

    @Test("Enforces source-cost limits and bypasses oversized documents")
    func sourceCostLimit() async throws {
        let parser = CountingMarkdownParser()
        let renderer = GitLabMarkdownRenderer(
            maximumDocumentCount: 10,
            maximumSourceCost: 8,
            parser: parser.parse
        )
        let first = try makeRequest(
            source: "1234",
            issueIID: 1
        )
        let second = try makeRequest(
            source: "5678",
            issueIID: 2
        )
        let third = try makeRequest(
            source: "abc",
            issueIID: 3
        )
        let oversized = try makeRequest(
            source: "123456789",
            issueIID: 4
        )

        _ = try await renderer.render(first)
        _ = try await renderer.render(second)
        _ = try await renderer.render(third)
        _ = try await renderer.render(oversized)
        _ = try await renderer.render(oversized)

        #expect(await renderer.cacheSourceCost <= 8)
        #expect(await renderer.cacheEntryCount == 2)
        #expect(await parser.callCount == 5)
    }

    @Test("Replaces stale content variants for one resource")
    func staleContentReplacement() async throws {
        let parser = CountingMarkdownParser()
        let renderer = GitLabMarkdownRenderer(
            parser: parser.parse
        )
        let first = try makeRequest(source: "First")
        let updated = try makeRequest(source: "Updated")

        _ = try await renderer.render(first)
        _ = try await renderer.render(updated)
        _ = try await renderer.render(first)

        #expect(await parser.callCount == 3)
        #expect(await renderer.cacheEntryCount == 1)
    }

    @Test("Coalesces identical in-flight renders")
    func inFlightCoalescing() async throws {
        let parser = GatedMarkdownParser()
        let renderer = GitLabMarkdownRenderer(
            parser: parser.parse
        )
        let request = try makeRequest(source: "Coalesced")

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

    @Test("Cancelling the last waiter cancels its parse")
    func cancellation() async throws {
        let parser = GatedMarkdownParser()
        let renderer = GitLabMarkdownRenderer(
            parser: parser.parse
        )
        let request = try makeRequest(source: "Cancelled")
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

    private func makeRequest(
        source: String,
        userID: Int = 1,
        issueIID: Int = 1
    ) throws -> GitLabMarkdownRequest {
        let host = try GitLabHost("https://gitlab.example.com")
        return GitLabMarkdownRequest(
            accountID: GitLabAccountID(
                host: host,
                userID: userID
            ),
            resource: .issue(
                projectID: 10,
                issueIID: issueIID
            ),
            source: source,
            webURL: URL(
                string:
                    "https://gitlab.example.com/group/project"
                    + "/-/issues/\(issueIID)"
            )
        )
    }
}

@Suite("GitLab Markdown presentation model")
@MainActor
struct GitLabMarkdownModelTests {
    @Test("Publishes rendered content")
    func publishesContent() async throws {
        let renderer = ControlledMarkdownRenderer()
        let model = GitLabMarkdownModel(renderer: renderer)
        let request = try makeRequest(
            source: "Published",
            issueIID: 1
        )

        await model.load(request)

        #expect(
            model.state
                == .loaded(
                    GitLabMarkdownDocument(
                        blocks: [
                            .paragraph(
                                GitLabMarkdownText(
                                    attributedString:
                                        AttributedString(
                                            "Published"
                                        )
                                )
                            ),
                        ]
                    )
                )
        )
    }

    @Test("A late result cannot replace a newer request")
    func latestRequestWins() async throws {
        let renderer = ControlledMarkdownRenderer(
            gatedSource: "First"
        )
        let model = GitLabMarkdownModel(renderer: renderer)
        let first = try makeRequest(
            source: "First",
            issueIID: 1
        )
        let second = try makeRequest(
            source: "Second",
            issueIID: 1
        )

        let firstTask = Task {
            await model.load(first)
        }
        await renderer.waitUntilGatedRequestStarts()
        await model.load(second)
        await renderer.finishGatedRequest()
        await firstTask.value

        #expect(model.document?.plainText == "Second")
    }

    @Test("Cancellation restores the prior visible document")
    func cancellationRestoresPriorState() async throws {
        let renderer = ControlledMarkdownRenderer(
            gatedSource: "Updated"
        )
        let model = GitLabMarkdownModel(renderer: renderer)
        let initial = try makeRequest(
            source: "Initial",
            issueIID: 1
        )
        let updated = try makeRequest(
            source: "Updated",
            issueIID: 1
        )
        await model.load(initial)

        let task = Task {
            await model.load(updated)
        }
        await renderer.waitUntilGatedRequestStarts()
        task.cancel()
        await renderer.finishGatedRequest()
        await task.value

        #expect(model.document?.plainText == "Initial")
        #expect(model.failureMessage == nil)
    }

    private func makeRequest(
        source: String,
        issueIID: Int
    ) throws -> GitLabMarkdownRequest {
        let host = try GitLabHost("https://gitlab.example.com")
        return GitLabMarkdownRequest(
            accountID: GitLabAccountID(
                host: host,
                userID: 1
            ),
            resource: .issue(
                projectID: 10,
                issueIID: issueIID
            ),
            source: source,
            webURL: URL(
                string:
                    "https://gitlab.example.com/group/project"
                    + "/-/issues/\(issueIID)"
            )
        )
    }
}

private actor CountingMarkdownParser {
    private(set) var callCount = 0

    func parse(
        _ request: GitLabMarkdownRequest
    ) async throws -> GitLabMarkdownDocument {
        callCount += 1
        return document(request.source)
    }
}

private actor GatedMarkdownParser {
    private(set) var callCount = 0
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var finishContinuation:
        CheckedContinuation<Void, Never>?
    private var cancellationWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var didStart = false
    private var wasCancelled = false

    func parse(
        _ request: GitLabMarkdownRequest
    ) async throws -> GitLabMarkdownDocument {
        callCount += 1
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        do {
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
        } catch {
            throw error
        }
        return document(request.source)
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

private actor ControlledMarkdownRenderer:
    GitLabMarkdownRendering
{
    private let gatedSource: String?
    private var didStartGatedRequest = false
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var finishContinuation:
        CheckedContinuation<Void, Never>?

    init(gatedSource: String? = nil) {
        self.gatedSource = gatedSource
    }

    func render(
        _ request: GitLabMarkdownRequest
    ) async throws -> GitLabMarkdownDocument {
        if request.source == gatedSource {
            didStartGatedRequest = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation {
                finishContinuation = $0
            }
        }
        return document(request.source)
    }

    func waitUntilGatedRequestStarts() async {
        guard !didStartGatedRequest else {
            return
        }
        await withCheckedContinuation {
            startWaiters.append($0)
        }
    }

    func finishGatedRequest() {
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

private nonisolated func document(
    _ text: String
) -> GitLabMarkdownDocument {
    GitLabMarkdownDocument(
        blocks: [
            .paragraph(
                GitLabMarkdownText(
                    attributedString:
                        AttributedString(text)
                )
            ),
        ]
    )
}
