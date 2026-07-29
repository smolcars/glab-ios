import Foundation
import Testing
@testable import Glab

@Suite("Merge request pipelines model")
@MainActor
struct GitLabMergeRequestPipelinesModelTests {
    @Test(
        "Loads next pages and retains their unique rows when page one refreshes"
    )
    func paginatesAndRetainsLoadedTail()
        async throws
    {
        let nextPageURL = URL(
            string:
                "https://gitlab.example.com/api/v4/projects/42/merge_requests/7/pipelines?page=2"
        )!
        let loader = PipelineHistoryLoader(
            firstPageResults: [
                .success(
                    event(
                        pipelines: [
                            try pipeline(
                                id: 3,
                                status: "running"
                            ),
                            try pipeline(
                                id: 2,
                                status: "success"
                            ),
                        ],
                        nextPageURL: nextPageURL
                    )
                ),
                .success(
                    event(
                        pipelines: [
                            try pipeline(
                                id: 4,
                                status: "pending"
                            ),
                            try pipeline(
                                id: 2,
                                status: "success"
                            ),
                        ],
                        nextPageURL: nextPageURL
                    )
                ),
            ],
            nextPageResults: [
                nextPageURL: .success(
                    page(
                        pipelines: [
                            try pipeline(
                                id: 1,
                                status: "failed"
                            ),
                        ]
                    )
                ),
            ]
        )
        let context = makeModel(loader: loader)

        await context.model.loadIfNeeded()
        let last = try #require(
            context.model.pipelines.items.last
        )
        await context.model
            .loadNextPageIfNeeded(after: last)
        await context.model.refresh()

        #expect(
            context.model.pipelines.items.map(\.id)
                == [4, 2, 3, 1]
        )
        #expect(
            await loader.recordedRefreshBehaviors()
                == [.ifStale, .always]
        )
    }

    @Test(
        "Polls active history once and stops after it becomes terminal"
    )
    func activeToTerminalPolling() async throws {
        let loader = PipelineHistoryLoader(
            firstPageResults: [
                .success(
                    event(
                        pipelines: [
                            try pipeline(
                                status: "running"
                            ),
                        ]
                    )
                ),
                .success(
                    event(
                        pipelines: [
                            try pipeline(
                                status: "success"
                            ),
                        ]
                    )
                ),
            ]
        )
        let pollGate = PipelinePollGate()
        let context = makeModel(
            loader: loader,
            pollWaiter: {
                try await pollGate.wait()
            }
        )

        let task = Task {
            await context.model.runVisible(
                isSceneActive: true
            )
        }
        await pollGate.waitUntilCallCount(1)
        await pollGate.advance()
        await task.value

        #expect(await pollGate.callCount == 1)
        #expect(
            context.model.pipelines.items
                .first?.status.rawValue
                == "success"
        )
        #expect(
            await loader.recordedRefreshBehaviors()
                == [.ifStale, .always]
        )
    }

    @Test(
        "Does not poll terminal, manual, or unknown pipeline states",
        arguments: [
            "success",
            "manual",
            "future_state",
        ]
    )
    func doesNotPollStableStates(
        status: String
    ) async throws {
        let loader = PipelineHistoryLoader(
            firstPageResults: [
                .success(
                    event(
                        pipelines: [
                            try pipeline(status: status),
                        ]
                    )
                ),
            ]
        )
        let pollGate = PipelinePollGate()
        let context = makeModel(
            loader: loader,
            pollWaiter: {
                try await pollGate.wait()
            }
        )

        await context.model.runVisible(
            isSceneActive: true
        )

        #expect(await pollGate.callCount == 0)
        #expect(
            await loader.recordedRefreshBehaviors()
                == [.ifStale]
        )
    }

    @Test(
        "Inactive scenes do not load or begin polling"
    )
    func inactiveSceneDoesNotLoad() async throws {
        let loader = PipelineHistoryLoader(
            firstPageResults: [
                .success(
                    event(
                        pipelines: [
                            try pipeline(
                                status: "running"
                            ),
                        ]
                    )
                ),
            ]
        )
        let pollGate = PipelinePollGate()
        let context = makeModel(
            loader: loader,
            pollWaiter: {
                try await pollGate.wait()
            }
        )

        await context.model.runVisible(
            isSceneActive: false
        )

        #expect(
            await loader.recordedRefreshBehaviors()
                .isEmpty
        )
        #expect(await pollGate.callCount == 0)
        #expect(!context.model.pipelines.hasLoaded)
    }

    @Test(
        "Cancelling visible work cancels its suspended poll"
    )
    func cancellationStopsPolling() async throws {
        let loader = PipelineHistoryLoader(
            firstPageResults: [
                .success(
                    event(
                        pipelines: [
                            try pipeline(
                                status: "running"
                            ),
                        ]
                    )
                ),
            ]
        )
        let pollGate = PipelinePollGate()
        let context = makeModel(
            loader: loader,
            pollWaiter: {
                try await pollGate.wait()
            }
        )
        let task = Task {
            await context.model.runVisible(
                isSceneActive: true
            )
        }
        await pollGate.waitUntilCallCount(1)

        task.cancel()
        await task.value

        #expect(await pollGate.callCount == 1)
        #expect(
            await loader.recordedRefreshBehaviors()
                == [.ifStale]
        )
    }

    @Test(
        "An account switch while loading prevents stale publication"
    )
    func accountSwitchRejectsResponse()
        async throws
    {
        let loader = PipelineHistoryLoader(
            firstPageResults: [
                .success(
                    event(
                        pipelines: [
                            try pipeline(
                                status: "running"
                            ),
                        ]
                    )
                ),
            ],
            suspendsFirstPage: true
        )
        let context = makeModel(loader: loader)
        let task = Task {
            await context.model.loadIfNeeded()
        }
        await loader.waitUntilFirstPageStarts()

        context.account.isCurrent = false
        await loader.resumeFirstPage()
        await task.value

        #expect(
            context.model.pipelines.items.isEmpty
        )
        #expect(!context.model.pipelines.hasLoaded)
        #expect(
            context.model.pipelines.loadError == nil
        )
    }

    @Test(
        "Authentication failure retains content and ends polling"
    )
    func authenticationFailureStopsPolling()
        async throws
    {
        let loader = PipelineHistoryLoader(
            firstPageResults: [
                .success(
                    event(
                        pipelines: [
                            try pipeline(
                                status: "running"
                            ),
                        ]
                    )
                ),
                .failure(.api(.unauthenticated)),
            ]
        )
        let pollGate = PipelinePollGate()
        let context = makeModel(
            loader: loader,
            pollWaiter: {
                try await pollGate.wait()
            }
        )
        let task = Task {
            await context.model.runVisible(
                isSceneActive: true
            )
        }
        await pollGate.waitUntilCallCount(1)
        await pollGate.advance()
        await task.value

        #expect(
            context.model.pipelines.items
                .first?.status.rawValue
                == "running"
        )
        #expect(
            context.model.authenticationFailure
                == .api(.unauthenticated)
        )
        #expect(await pollGate.callCount == 1)
    }

    @Test(
        "A transient poll failure waits for another bounded tick"
    )
    func transientFailureCanRecover()
        async throws
    {
        let loader = PipelineHistoryLoader(
            firstPageResults: [
                .success(
                    event(
                        pipelines: [
                            try pipeline(
                                status: "running"
                            ),
                        ]
                    )
                ),
                .failure(.api(.server(statusCode: 500))),
                .success(
                    event(
                        pipelines: [
                            try pipeline(
                                status: "success"
                            ),
                        ]
                    )
                ),
            ]
        )
        let pollGate = PipelinePollGate()
        let context = makeModel(
            loader: loader,
            pollWaiter: {
                try await pollGate.wait()
            }
        )
        let task = Task {
            await context.model.runVisible(
                isSceneActive: true
            )
        }

        await pollGate.waitUntilCallCount(1)
        await pollGate.advance()
        await pollGate.waitUntilCallCount(2)
        await pollGate.advance()
        await task.value

        #expect(await pollGate.callCount == 2)
        #expect(
            context.model.pipelines.items
                .first?.status.rawValue
                == "success"
        )
        #expect(
            context.model.pipelines.loadError == nil
        )
    }

    private func makeModel(
        loader: any GitLabPipelineLoading,
        pollWaiter:
            @escaping GitLabPipelinePollWaiter = {
                try await Task.sleep(
                    for: .seconds(60 * 60)
                )
            }
    ) -> PipelineHistoryModelContext {
        let account = PipelineCurrentAccountBox()
        let accountID = GitLabAccountID(
            host:
                try! GitLabHost(
                    "gitlab.example.com"
                ),
            userID: 17
        )
        let model =
            GitLabMergeRequestPipelinesModel(
                accountID: accountID,
                route:
                    GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 7
                    ),
                loader: loader,
                pollWaiter: pollWaiter,
                isAccountCurrent: {
                    account.isCurrent
                }
            )
        return PipelineHistoryModelContext(
            model: model,
            account: account
        )
    }

    private func pipeline(
        id: Int = 501,
        status: String
    ) throws -> GitLabPipeline {
        try JSONDecoder().decode(
            GitLabPipeline.self,
            from:
                Data(
                    """
                    {
                      "id": \(id),
                      "project_id": 42,
                      "sha": "abc\(id)",
                      "ref": "main",
                      "status": "\(status)"
                    }
                    """.utf8
                )
        )
    }

    private func page(
        pipelines: [GitLabPipeline],
        nextPageURL: URL? = nil
    ) -> GitLabResourcePage<GitLabPipeline> {
        GitLabResourcePage(
            items: pipelines,
            nextPageURL: nextPageURL
        )
    }

    private func event(
        pipelines: [GitLabPipeline],
        nextPageURL: URL? = nil
    ) -> GitLabResourcePageEvent<GitLabPipeline> {
        GitLabResourcePageEvent(
            page: page(
                pipelines: pipelines,
                nextPageURL: nextPageURL
            ),
            source: .network
        )
    }
}

@MainActor
private struct PipelineHistoryModelContext {
    let model: GitLabMergeRequestPipelinesModel
    let account: PipelineCurrentAccountBox
}

@MainActor
private final class PipelineCurrentAccountBox {
    var isCurrent = true
}

private actor PipelineHistoryLoader:
    GitLabPipelineLoading
{
    private var firstPageResults:
        [
            Result<
                GitLabResourcePageEvent<
                    GitLabPipeline
                >,
                GitLabSessionClientError
            >
        ]
    private var nextPageResults:
        [
            URL:
                Result<
                    GitLabResourcePage<
                        GitLabPipeline
                    >,
                    GitLabSessionClientError
                >
        ]
    private var refreshBehaviors:
        [GitLabCacheRefreshBehavior] = []
    private let suspendsFirstPage: Bool
    private var firstPageStarted = false
    private var firstPageContinuation:
        CheckedContinuation<Void, Never>?

    init(
        firstPageResults:
            [
                Result<
                    GitLabResourcePageEvent<
                        GitLabPipeline
                    >,
                    GitLabSessionClientError
                >
            ],
        nextPageResults:
            [
                URL:
                    Result<
                        GitLabResourcePage<
                            GitLabPipeline
                        >,
                        GitLabSessionClientError
                    >
            ] = [:],
        suspendsFirstPage: Bool = false
    ) {
        self.firstPageResults =
            firstPageResults
        self.nextPageResults =
            nextPageResults
        self.suspendsFirstPage =
            suspendsFirstPage
    }

    func recordedRefreshBehaviors()
        -> [GitLabCacheRefreshBehavior]
    {
        refreshBehaviors
    }

    func waitUntilFirstPageStarts() async {
        while !firstPageStarted {
            await Task.yield()
        }
    }

    func resumeFirstPage() {
        firstPageContinuation?.resume()
        firstPageContinuation = nil
    }

    func loadMergeRequestPipelinesPage(
        at route: GitLabMergeRequestRoute,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabPipeline>
    {
        guard
            route.projectID == 42,
            route.mergeRequestIID == 7,
            let nextPageURL,
            let result =
                nextPageResults.removeValue(
                    forKey: nextPageURL
                )
        else {
            throw .api(.invalidResponse)
        }
        return try result.get()
    }

    func loadMergeRequestPipelinesFirstPage(
        at route: GitLabMergeRequestRoute,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabPipeline
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        guard
            route.projectID == 42,
            route.mergeRequestIID == 7,
            !firstPageResults.isEmpty
        else {
            throw .api(.invalidResponse)
        }

        refreshBehaviors.append(
            refreshBehavior
        )
        firstPageStarted = true
        if
            suspendsFirstPage,
            refreshBehaviors.count == 1
        {
            await withCheckedContinuation {
                firstPageContinuation = $0
            }
        }

        let result =
            firstPageResults.removeFirst()
        await onPage(try result.get())
    }

    func loadPipeline(
        at route: GitLabPipelineRoute,
        cacheLifetime:
            GitLabPipelineCacheLifetime,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabPipeline
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        fatalError("Not used by history model tests")
    }

    func loadPipelineJobsPage(
        at route: GitLabPipelineRoute,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabPipelineJob>
    {
        fatalError("Not used by history model tests")
    }

    func loadPipelineJobsFirstPage(
        at route: GitLabPipelineRoute,
        cacheLifetime:
            GitLabPipelineCacheLifetime,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabPipelineJob
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        fatalError("Not used by history model tests")
    }

    func loadPipelineTriggerJobsPage(
        at route: GitLabPipelineRoute,
        capability:
            GitLabPipelineTriggerJobsCapability,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineTriggerJobsPage
    {
        fatalError("Not used by history model tests")
    }

    func loadPipelineTriggerJobsFirstPage(
        at route: GitLabPipelineRoute,
        capability:
            GitLabPipelineTriggerJobsCapability,
        cacheLifetime:
            GitLabPipelineCacheLifetime,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabPipelineTriggerJob
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineTriggerJobsCapability
    {
        fatalError("Not used by history model tests")
    }
}
