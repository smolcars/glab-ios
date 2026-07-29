import Foundation
import Testing
@testable import Glab

@Suite("GitLab job trace model")
@MainActor
struct GitLabJobTraceModelTests {
    @Test("Publishes a cached terminal trace without downloading")
    func opensCachedTerminalTrace() async throws {
        let fixture = try Fixture(
            status: "success",
            cachedLineCount: 3
        )

        await fixture.model.loadIfNeeded()

        #expect(
            fixture.model.state
                == .ready(
                    fixture.cachedDescriptor,
                    source: .cache
                )
        )
        #expect(fixture.model.document != nil)
        #expect(await fixture.loader.loadCallCount == 0)
        #expect(!fixture.model.canRefresh)
    }

    @Test("A cached active trace stays readable until explicit refresh commits")
    func refreshRetainsCachedTrace() async throws {
        let fixture = try Fixture(
            status: "running",
            cachedLineCount: 2,
            loadResults: [
                .success(
                    try Self.descriptor(
                        key: nil,
                        marker: "replacement",
                        lineCount: 4
                    )
                ),
            ],
            gateLoads: true
        )

        await fixture.model.loadIfNeeded()
        #expect(fixture.model.canRefresh)
        #expect(await fixture.loader.loadCallCount == 0)

        let refresh = Task {
            await fixture.model.refresh()
        }
        await fixture.loader.waitUntilLoadStarts()

        #expect(fixture.model.isRefreshing)
        #expect(
            fixture.model.descriptor
                == fixture.cachedDescriptor
        )

        await fixture.loader.releaseLoad()
        await refresh.value

        #expect(!fixture.model.isRefreshing)
        #expect(
            fixture.model.descriptor?
                .lineCount == 4
        )
        #expect(
            fixture.model.source == .refresh
        )
    }

    @Test("A missing cache downloads once and overlapping opens coalesce")
    func downloadsMissingTraceOnce() async throws {
        let fixture = try Fixture(
            cachedLineCount: nil,
            loadResults: [
                .success(
                    try Self.descriptor(
                        key: nil,
                        marker: "network",
                        lineCount: 1
                    )
                ),
            ],
            gateLoads: true
        )

        let first = Task {
            await fixture.model.loadIfNeeded()
        }
        await fixture.loader.waitUntilLoadStarts()
        let second = Task {
            await fixture.model.loadIfNeeded()
        }
        await Task.yield()

        #expect(fixture.model.state == .loading)
        #expect(await fixture.loader.loadCallCount == 1)

        await fixture.loader.releaseLoad()
        await first.value
        await second.value

        #expect(
            fixture.model.source == .network
        )
        #expect(await fixture.loader.loadCallCount == 1)
    }

    @Test("An empty response is distinct from a missing trace")
    func distinguishesEmptyAndMissingTrace() async throws {
        let empty = try Fixture(
            cachedLineCount: nil,
            loadResults: [
                .success(
                    try Self.descriptor(
                        key: nil,
                        marker: "empty",
                        lineCount: 0
                    )
                ),
            ]
        )
        await empty.model.loadIfNeeded()

        #expect(
            empty.model.state
                == .empty(
                    try Self.descriptor(
                        key: empty.key,
                        marker: "empty",
                        lineCount: 0
                    ),
                    source: .network
                )
        )
        #expect(empty.model.document == nil)

        let missing = try Fixture(
            cachedLineCount: nil,
            loadResults: [
                .failure(.noTrace),
            ]
        )
        await missing.model.loadIfNeeded()

        #expect(missing.model.state == .noTrace)
    }

    @Test("A failed refresh retains cached content and explains a missing trace")
    func failedRefreshRetainsCache() async throws {
        let fixture = try Fixture(
            status: "running",
            cachedLineCount: 5,
            loadResults: [
                .failure(.noTrace),
            ]
        )
        await fixture.model.loadIfNeeded()

        await fixture.model.refresh()

        #expect(
            fixture.model.descriptor
                == fixture.cachedDescriptor
        )
        #expect(
            fixture.model.refreshError
                == .noTrace
        )
        #expect(fixture.model.document != nil)
    }

    @Test("Surfaces local bounds and account authentication failures")
    func surfacesTypedFailures() async throws {
        let oversized = try Fixture(
            cachedLineCount: nil,
            loadResults: [
                .failure(.tooLarge),
            ]
        )
        await oversized.model.loadIfNeeded()
        #expect(oversized.model.state == .tooLarge)

        let authenticationError =
            GitLabSessionClientError
            .api(.unauthenticated)
        let unauthenticated = try Fixture(
            cachedLineCount: nil,
            loadResults: [
                .failure(
                    .session(
                        authenticationError
                    )
                ),
            ]
        )
        await unauthenticated.model
            .loadIfNeeded()

        #expect(
            unauthenticated.model
                .authenticationFailure
                == authenticationError
        )
    }

    @Test("Account replacement suppresses an in-flight result")
    func suppressesStaleAccountResult() async throws {
        let fixture = try Fixture(
            cachedLineCount: nil,
            loadResults: [
                .success(
                    try Self.descriptor(
                        key: nil,
                        marker: "stale",
                        lineCount: 2
                    )
                ),
            ],
            gateLoads: true
        )
        let task = Task {
            await fixture.model.loadIfNeeded()
        }
        await fixture.loader.waitUntilLoadStarts()

        fixture.currentAccount.isCurrent = false
        await fixture.loader.releaseLoad()
        await task.value

        #expect(fixture.model.state == .loading)
        #expect(fixture.model.document == nil)
    }

    @Test("Closing the model cancels an in-flight load")
    func cancellationStopsLoad() async throws {
        let fixture = try Fixture(
            cachedLineCount: nil,
            loadResults: [
                .success(
                    try Self.descriptor(
                        key: nil,
                        marker: "ignored",
                        lineCount: 1
                    )
                ),
            ],
            gateLoads: true
        )
        let task = Task {
            await fixture.model.loadIfNeeded()
        }
        await fixture.loader.waitUntilLoadStarts()

        await fixture.model.cancel()
        await task.value

        #expect(await fixture.loader.cancellationCount == 1)
        #expect(fixture.model.document == nil)
        #expect(fixture.model.state == .idle)
    }

    @Test("Rejects a descriptor published for another route")
    func rejectsMismatchedDescriptor()
        async throws
    {
        let fixture = try Fixture(
            cachedLineCount: nil,
            loadResults: [
                .success(
                    try Self.descriptor(
                        key:
                            GitLabJobTraceKey(
                                accountID:
                                    Self.account(),
                                route:
                                    try #require(
                                        GitLabJobTraceRoute(
                                            projectID: 99,
                                            jobID: 100
                                        )
                                    )
                            ),
                        marker: "mismatch",
                        lineCount: 1
                    )
                ),
            ],
            remapLoadKeys: false
        )

        await fixture.model.loadIfNeeded()

        #expect(
            fixture.model.state
                == .failed(.invalidTrace)
        )
        #expect(fixture.model.document == nil)
    }

    @Test("Search selection wraps and reuses preloaded lines")
    func searchSelectionWraps() async throws {
        let reader = TraceModelReader(
            searchResult:
                GitLabJobTraceSearchResult(
                    lineIndexes: [1, 4],
                    selectedMatchPosition: nil,
                    hasAdditionalMatches: false
                )
        )
        let fixture = try Fixture(
            cachedLineCount: 6,
            documentFactory: {
                descriptor in
                GitLabJobTraceDocument(
                    descriptor: descriptor,
                    reader: reader
                )
            }
        )
        await fixture.model.loadIfNeeded()

        await fixture.model.search("failed")
        let first =
            await fixture.model
            .selectNextMatch()
        let second =
            await fixture.model
            .selectNextMatch()
        let wrapped =
            await fixture.model
            .selectNextMatch()
        let previous =
            await fixture.model
            .selectPreviousMatch()

        #expect(
            [first, second, wrapped, previous]
                == [1, 4, 1, 4]
        )
        #expect(
            await reader.lineRanges
                == [
                    1..<2,
                    4..<5,
                ]
        )
    }
}

@Suite("Pipeline job trace routing")
struct GitLabPipelineJobTraceRoutingTests {
    @Test("Only ordinary jobs produce a native trace context")
    func routesOnlyOrdinaryJobs() async throws {
        let stages =
            await GitLabPipelineStageProjector
            .project(
                jobs: [
                    try decode(
                        """
                        {
                          "id": 800,
                          "name": "unit tests",
                          "stage": "test",
                          "status": "failed",
                          "archived": true,
                          "erased_at": "2026-07-29T01:05:50Z",
                          "web_url": "https://gitlab.example.com/group/project/-/jobs/800"
                        }
                        """
                    ),
                ],
                triggerJobs: [
                    try decode(
                        """
                        {
                          "id": 801,
                          "name": "child",
                          "stage": "test",
                          "status": "success",
                          "downstream_pipeline": {
                            "id": 601,
                            "project_id": 84,
                            "sha": "def456",
                            "ref": "main",
                            "status": "success"
                          }
                        }
                        """
                    ),
                ]
            )
        let rows = stages.flatMap(\.rows)
        let ordinary = try #require(
            rows.first {
                $0.id == .job(800)
            }?
            .jobTraceContext(
                projectID: 42
            )
        )
        let trigger = try #require(
            rows.first {
                $0.id == .triggerJob(801)
            }
        )

        #expect(
            ordinary.route
                == GitLabJobTraceRoute(
                    projectID: 42,
                    jobID: 800
                )
        )
        #expect(ordinary.jobName == "unit tests")
        #expect(ordinary.archived == true)
        #expect(
            ordinary.webURL?
                .scheme == "https"
        )
        #expect(
            trigger.jobTraceContext(
                projectID: 42
            ) == nil
        )
        if
            case let .triggerJob(job) =
                trigger.content
        {
            #expect(
                job.downstreamRoute
                    == GitLabPipelineRoute(
                        projectID: 84,
                        pipelineID: 601
                    )
            )
        } else {
            Issue.record(
                "Expected the trigger job to remain a child-pipeline row."
            )
        }
    }
}

private extension GitLabJobTraceModelTests {
    struct Fixture {
        let key: GitLabJobTraceKey
        let cachedDescriptor:
            GitLabJobTraceDescriptor
        let loader: TraceModelLoader
        let currentAccount:
            TraceModelCurrentAccount
        let model: GitLabJobTraceModel

        @MainActor
        init(
            status: String = "running",
            cachedLineCount: Int?,
            loadResults: [
                Result<
                    GitLabJobTraceDescriptor,
                    GitLabJobTraceLoadError
                >
            ] = [],
            gateLoads: Bool = false,
            remapLoadKeys: Bool = true,
            documentFactory:
                @escaping GitLabJobTraceDocumentFactory = {
                    GitLabJobTraceDocument(
                        descriptor: $0
                    )
                }
        ) throws {
            let accountID = try account()
            let route = try #require(
                GitLabJobTraceRoute(
                    projectID: 42,
                    jobID: 800
                )
            )
            let resolvedKey =
                GitLabJobTraceKey(
                accountID: accountID,
                route: route
            )
            let resolvedCachedDescriptor =
                try GitLabJobTraceModelTests
                .descriptor(
                    key: resolvedKey,
                    marker: "cache",
                    lineCount:
                        cachedLineCount ?? 0
                )
            let remappedResults =
                loadResults.map { result in
                    result.map { value in
                        guard remapLoadKeys else {
                            return value
                        }
                        return GitLabJobTraceDescriptor(
                            key: resolvedKey,
                            traceFileURL:
                                value
                                .traceFileURL,
                            indexFileURL:
                                value
                                .indexFileURL,
                            byteCount:
                                value.byteCount,
                            lineCount:
                                value.lineCount,
                            storedAt:
                                value.storedAt,
                            rawContentDigest:
                                value
                                .rawContentDigest,
                            longLineCount:
                                value
                                .longLineCount,
                            firstLikelyFailure:
                                value
                                .firstLikelyFailure
                        )
                    }
                }
            let resolvedLoader =
                TraceModelLoader(
                cachedDescriptor:
                    cachedLineCount == nil
                    ? nil
                    : resolvedCachedDescriptor,
                loadResults:
                    remappedResults,
                gateLoads: gateLoads
            )
            let resolvedCurrentAccount =
                TraceModelCurrentAccount()
            let context = try #require(
                GitLabJobTraceContext(
                    route: route,
                    jobName: "unit tests",
                    status:
                        GitLabCIStatus(
                            rawValue: status
                        ),
                    archived: nil,
                    erasedAt: nil,
                    webURL:
                        URL(
                            string:
                                "https://gitlab.example.com/group/project/-/jobs/800"
                    )
                )
            )
            let resolvedModel =
                GitLabJobTraceModel(
                accountID: accountID,
                context: context,
                loader: resolvedLoader,
                documentFactory:
                    documentFactory,
                isAccountCurrent: {
                    resolvedCurrentAccount
                        .isCurrent
                }
            )
            key = resolvedKey
            cachedDescriptor =
                resolvedCachedDescriptor
            loader = resolvedLoader
            currentAccount =
                resolvedCurrentAccount
            model = resolvedModel
        }
    }

    static func account()
        throws -> GitLabAccountID
    {
        GitLabAccountID(
            host:
                try GitLabHost(
                    "gitlab.example.com"
                ),
            userID: 7
        )
    }

    static func descriptor(
        key: GitLabJobTraceKey?,
        marker: String,
        lineCount: Int
    ) throws -> GitLabJobTraceDescriptor {
        let resolvedKey =
            try key
            ?? GitLabJobTraceKey(
                accountID: account(),
                route:
                    #require(
                        GitLabJobTraceRoute(
                            projectID: 42,
                            jobID: 800
                        )
                    )
            )
        return GitLabJobTraceDescriptor(
            key: resolvedKey,
            traceFileURL:
                URL(
                    filePath:
                        "/tmp/\(marker).raw"
                ),
            indexFileURL:
                URL(
                    filePath:
                        "/tmp/\(marker).idx"
                ),
            byteCount: lineCount * 8,
            lineCount: lineCount,
            storedAt:
                Date(
                    timeIntervalSince1970:
                        marker == "cache"
                        ? 1_000
                        : 2_000
                ),
            rawContentDigest: marker,
            longLineCount: 0
        )
    }
}

@MainActor
private final class TraceModelCurrentAccount {
    var isCurrent = true
}

private actor TraceModelLoader:
    GitLabJobTraceLoading
{
    private let cached:
        GitLabJobTraceDescriptor?
    private var results: [
        Result<
            GitLabJobTraceDescriptor,
            GitLabJobTraceLoadError
        >
    ]
    private let gateLoads: Bool
    private var loadWaiters: [
        UUID:
            CheckedContinuation<
                Void,
                any Error
            >
    ] = [:]
    private var calls = 0
    private var cancellations = 0
    private var isReleased = false

    init(
        cachedDescriptor:
            GitLabJobTraceDescriptor?,
        loadResults: [
            Result<
                GitLabJobTraceDescriptor,
                GitLabJobTraceLoadError
            >
        ],
        gateLoads: Bool
    ) {
        cached = cachedDescriptor
        results = loadResults
        self.gateLoads = gateLoads
    }

    var loadCallCount: Int {
        calls
    }

    var cancellationCount: Int {
        cancellations
    }

    func cachedDescriptor(
        for key: GitLabJobTraceKey
    ) -> GitLabJobTraceDescriptor? {
        guard cached?.key == key else {
            return nil
        }
        return cached
    }

    func loadTrace(
        for key: GitLabJobTraceKey
    ) async throws(GitLabJobTraceLoadError)
        -> GitLabJobTraceDescriptor
    {
        calls += 1
        if gateLoads {
            do {
                try await waitForRelease()
            } catch {
                cancellations += 1
                throw .cancelled
            }
        }
        guard !results.isEmpty else {
            throw .storage
        }
        return try results.removeFirst()
            .get()
    }

    func waitUntilLoadStarts() async {
        while calls == 0 {
            await Task.yield()
        }
    }

    func releaseLoad() {
        isReleased = true
        for continuation in
            loadWaiters.values
        {
            continuation.resume()
        }
        loadWaiters.removeAll()
    }

    private func waitForRelease()
        async throws
    {
        guard !isReleased else {
            return
        }
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
                        } else if isReleased {
                            continuation
                                .resume()
                        } else {
                            loadWaiters[id] =
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
        loadWaiters
            .removeValue(forKey: id)?
            .resume(
                throwing:
                    CancellationError()
            )
    }
}

private actor TraceModelReader:
    GitLabJobTraceReading
{
    let searchResult:
        GitLabJobTraceSearchResult
    private(set) var lineRanges:
        [Range<Int>] = []

    init(
        searchResult:
            GitLabJobTraceSearchResult
    ) {
        self.searchResult = searchResult
    }

    func lines(
        in range: Range<Int>,
        descriptor:
            GitLabJobTraceDescriptor,
        maximumLineByteCount: Int
    ) -> [GitLabJobTraceLine] {
        lineRanges.append(range)
        return range.map {
            GitLabJobTraceLine(
                index: $0,
                text: "line \($0)",
                rawByteCount: 6,
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
    ) -> GitLabJobTraceSearchResult {
        searchResult
    }
}

private func decode<Value>(
    _ json: String
) throws -> Value
where Value: Decodable & Sendable {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy =
        .iso8601
    return try decoder.decode(
        Value.self,
        from: Data(json.utf8)
    )
}
