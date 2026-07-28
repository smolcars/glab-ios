import Foundation
import Testing
@testable import Glab

@Suite("GitLab diff presentation model")
@MainActor
struct GitLabDiffModelTests {
    @Test("Publishes a parsed document")
    func publishesDocument() async throws {
        let renderer = ControlledDiffRenderer()
        let model = GitLabDiffModel(
            renderer: renderer
        )
        let request = try makeRequest(
            source: "published"
        )

        await model.load(request)

        #expect(
            model.state
                == .loaded(
                    testDocument("published")
                )
        )
    }

    @Test("A late parse cannot replace a newer file selection")
    func latestSelectionWins() async throws {
        let renderer = ControlledDiffRenderer(
            gatedSource: "first"
        )
        let model = GitLabDiffModel(
            renderer: renderer
        )
        let first = try makeRequest(
            source: "first"
        )
        let second = try makeRequest(
            source: "second",
            newPath: "Second.swift"
        )

        let firstTask = Task {
            await model.load(first)
        }
        await renderer.waitUntilGatedRequestStarts()
        await model.load(second)
        await renderer.finishGatedRequest()
        await firstTask.value

        #expect(
            model.document
                == testDocument("second")
        )
    }

    @Test("Cancellation does not publish a failure")
    func cancellation() async throws {
        let renderer = ControlledDiffRenderer(
            gatedSource: "cancelled"
        )
        let model = GitLabDiffModel(
            renderer: renderer
        )
        let request = try makeRequest(
            source: "cancelled"
        )
        let task = Task {
            await model.load(request)
        }
        await renderer.waitUntilGatedRequestStarts()

        task.cancel()
        await renderer.finishGatedRequest()
        await task.value

        #expect(model.state == .idle)
    }

    @Test("Publishes a readable parser failure")
    func failure() async throws {
        let renderer = FailingDiffRenderer()
        let model = GitLabDiffModel(
            renderer: renderer
        )

        await model.load(
            try makeRequest(source: "broken")
        )

        #expect(
            model.state
                == .failed(
                    "GitLab returned a malformed diff hunk at line 3."
                )
        )
    }

    private func makeRequest(
        source: String,
        newPath: String = "File.swift"
    ) throws -> GitLabDiffRequest {
        let host = try GitLabHost(
            "https://gitlab.example.com"
        )
        return GitLabDiffRequest(
            accountID: GitLabAccountID(
                host: host,
                userID: 1
            ),
            route: GitLabMergeRequestRoute(
                projectID: 42,
                mergeRequestIID: 7
            ),
            headSHA: "head",
            oldPath: "File.swift",
            newPath: newPath,
            source: source
        )
    }
}

private actor ControlledDiffRenderer:
    GitLabDiffRendering
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
        _ request: GitLabDiffRequest
    ) async throws -> GitLabParsedDiffDocument {
        if request.source == gatedSource {
            didStartGatedRequest = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation {
                finishContinuation = $0
            }
            try Task.checkCancellation()
        }
        return testDocument(request.source)
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

private actor FailingDiffRenderer:
    GitLabDiffRendering
{
    func render(
        _ request: GitLabDiffRequest
    ) async throws -> GitLabParsedDiffDocument {
        throw GitLabUnifiedDiffParserError
            .malformedHunk(sourceLine: 3)
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
