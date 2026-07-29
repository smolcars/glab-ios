import Foundation
import Testing
@testable import Glab

@Suite("Pipeline detail model")
@MainActor
struct GitLabPipelineDetailModelTests {
    @Test(
        "Loads metadata, jobs, and trigger jobs independently and projects stages"
    )
    func loadsIndependentSurfaces()
        async throws
    {
        let loader = PipelineDetailLoader(
            pipelineResults: [
                .success(
                    pipelineEvent(
                        try pipeline(
                            status: "running"
                        )
                    )
                ),
            ],
            jobFirstPageResults: [
                .success(
                    jobEvent([
                        try job(
                            id: 90,
                            name: "unit tests",
                            stage: "test",
                            status: "running"
                        ),
                    ])
                ),
            ],
            triggerFirstPageResults: [
                .success(
                    PipelineTriggerFirstPageResult(
                        event:
                            triggerEvent([
                                try triggerJob(
                                    id: 80,
                                    name: "deploy child",
                                    stage: "deploy",
                                    status: "pending"
                                ),
                            ]),
                        selectedCapability:
                            .legacy
                    )
                ),
            ]
        )
        let context = makeModel(loader: loader)

        await context.model.loadIfNeeded()

        #expect(
            context.model.pipeline?.status
                .rawValue == "running"
        )
        #expect(
            context.model.jobs.items.map(\.id)
                == [90]
        )
        #expect(
            context.model.triggerJobs.items
                .map(\.id) == [80]
        )
        #expect(
            context.model.stages.map(\.name)
                == ["test", "deploy"]
        )
        #expect(
            context.model.stages
                .flatMap(\.rows)
                .map(\.id)
                == [
                    .job(90),
                    .triggerJob(80),
                ]
        )
        #expect(
            await loader
                .recordedTriggerCapabilities()
                == [.preferred]
        )
    }

    @Test(
        "A job failure retains pipeline metadata and trigger jobs"
    )
    func jobFailureIsIndependent()
        async throws
    {
        let loader = PipelineDetailLoader(
            pipelineResults: [
                .success(
                    pipelineEvent(
                        try pipeline(
                            status: "success"
                        )
                    )
                ),
            ],
            jobFirstPageResults: [
                .failure(
                    .api(
                        .server(
                            statusCode: 503
                        )
                    )
                ),
            ],
            triggerFirstPageResults: [
                .success(
                    PipelineTriggerFirstPageResult(
                        event:
                            triggerEvent([
                                try triggerJob(
                                    status: "success"
                                ),
                            ]),
                        selectedCapability:
                            .preferred
                    )
                ),
            ]
        )
        let context = makeModel(loader: loader)

        await context.model.loadIfNeeded()

        #expect(
            context.model.pipeline?.status
                .rawValue == "success"
        )
        #expect(
            context.model.jobs.loadError
                == .api(
                    .server(
                        statusCode: 503
                    )
                )
        )
        #expect(
            context.model.triggerJobs.items
                .count == 1
        )
        #expect(
            context.model.stages
                .flatMap(\.rows)
                .map(\.id)
                == [.triggerJob(801)]
        )
    }

    @Test(
        "A trigger failure retains ordinary jobs and stays scoped"
    )
    func triggerFailureIsIndependent()
        async throws
    {
        let loader = PipelineDetailLoader(
            pipelineResults: [
                .success(
                    pipelineEvent(
                        try pipeline(
                            status: "success"
                        )
                    )
                ),
            ],
            jobFirstPageResults: [
                .success(
                    jobEvent([
                        try job(
                            status: "success"
                        ),
                    ])
                ),
            ],
            triggerFirstPageResults: [
                .failure(.api(.forbidden)),
            ]
        )
        let context = makeModel(loader: loader)

        await context.model.loadIfNeeded()

        #expect(
            context.model.jobs.items.count
                == 1
        )
        #expect(
            context.model.triggerJobs
                .loadError == .api(.forbidden)
        )
        #expect(
            context.model.stages
                .flatMap(\.rows)
                .map(\.id)
                == [.job(800)]
        )
        #expect(
            context.model.authenticationFailure
                == nil
        )
    }

    @Test(
        "Remembers a legacy trigger endpoint across refreshes"
    )
    func remembersLegacyCapability()
        async throws
    {
        let loader = PipelineDetailLoader(
            pipelineResults: [
                .success(
                    pipelineEvent(
                        try pipeline(
                            status: "success"
                        )
                    )
                ),
                .success(
                    pipelineEvent(
                        try pipeline(
                            status: "success"
                        )
                    )
                ),
            ],
            jobFirstPageResults: [
                .success(jobEvent([])),
                .success(jobEvent([])),
            ],
            triggerFirstPageResults: [
                .success(
                    PipelineTriggerFirstPageResult(
                        event: triggerEvent([]),
                        selectedCapability:
                            .legacy
                    )
                ),
                .success(
                    PipelineTriggerFirstPageResult(
                        event: triggerEvent([]),
                        selectedCapability:
                            .legacy
                    )
                ),
            ]
        )
        let context = makeModel(loader: loader)

        await context.model.loadIfNeeded()
        await context.model.refresh()

        #expect(
            await loader
                .recordedTriggerCapabilities()
                == [.preferred, .legacy]
        )
    }

    @Test(
        "A first-page refresh retains later jobs and regroups their stages"
    )
    func retainsLaterJobPages()
        async throws
    {
        let nextPageURL = URL(
            string:
                "https://gitlab.example.com/api/v4/projects/42/pipelines/501/jobs?page=2"
        )!
        let loader = PipelineDetailLoader(
            pipelineResults: [
                .success(
                    pipelineEvent(
                        try pipeline(
                            status: "running"
                        )
                    )
                ),
                .success(
                    pipelineEvent(
                        try pipeline(
                            status: "running"
                        )
                    )
                ),
            ],
            jobFirstPageResults: [
                .success(
                    jobEvent(
                        [
                            try job(
                                id: 3,
                                name: "test",
                                stage: "test",
                                status: "running"
                            ),
                            try job(
                                id: 2,
                                name: "build",
                                stage: "build",
                                status: "success"
                            ),
                        ],
                        nextPageURL: nextPageURL
                    )
                ),
                .success(
                    jobEvent(
                        [
                            try job(
                                id: 4,
                                name: "lint",
                                stage: "test",
                                status: "success"
                            ),
                            try job(
                                id: 2,
                                name: "build",
                                stage: "build",
                                status: "success"
                            ),
                        ],
                        nextPageURL: nextPageURL
                    )
                ),
            ],
            jobNextPageResults: [
                nextPageURL:
                    .success(
                        GitLabResourcePage(
                            items: [
                                try job(
                                    id: 1,
                                    name: "deploy",
                                    stage: "deploy",
                                    status: "manual"
                                ),
                            ],
                            nextPageURL: nil
                        )
                    ),
            ],
            triggerFirstPageResults: [
                .success(
                    PipelineTriggerFirstPageResult(
                        event: triggerEvent([]),
                        selectedCapability:
                            .preferred
                    )
                ),
                .success(
                    PipelineTriggerFirstPageResult(
                        event: triggerEvent([]),
                        selectedCapability:
                            .preferred
                    )
                ),
            ]
        )
        let context = makeModel(loader: loader)

        await context.model.loadIfNeeded()
        let last = try #require(
            context.model.jobs.items.last
        )
        await context.model
            .loadNextJobsPageIfNeeded(
                after: last
            )
        await context.model.refresh()

        #expect(
            context.model.jobs.items.map(\.id)
                == [4, 2, 3, 1]
        )
        #expect(
            context.model.stages.map(\.name)
                == ["test", "build", "deploy"]
        )
    }

    @Test(
        "Visible polling refreshes active content and stops when all work is terminal"
    )
    func pollsUntilTerminal() async throws {
        let loader = PipelineDetailLoader(
            pipelineResults: [
                .success(
                    pipelineEvent(
                        try pipeline(
                            status: "running"
                        )
                    )
                ),
                .success(
                    pipelineEvent(
                        try pipeline(
                            status: "success"
                        )
                    )
                ),
            ],
            jobFirstPageResults: [
                .success(
                    jobEvent([
                        try job(status: "running"),
                    ])
                ),
                .success(
                    jobEvent([
                        try job(status: "success"),
                    ])
                ),
            ],
            triggerFirstPageResults: [
                .success(
                    PipelineTriggerFirstPageResult(
                        event: triggerEvent([]),
                        selectedCapability:
                            .preferred
                    )
                ),
                .success(
                    PipelineTriggerFirstPageResult(
                        event: triggerEvent([]),
                        selectedCapability:
                            .preferred
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
            context.model.pipeline?.status
                .rawValue == "success"
        )
        #expect(
            context.model.jobs.items
                .first?.status.rawValue
                == "success"
        )
    }

    @Test(
        "An authentication failure in one surface is forwarded"
    )
    func forwardsAuthenticationFailure()
        async throws
    {
        let loader = PipelineDetailLoader(
            pipelineResults: [
                .success(
                    pipelineEvent(
                        try pipeline(
                            status: "success"
                        )
                    )
                ),
            ],
            jobFirstPageResults: [
                .success(jobEvent([])),
            ],
            triggerFirstPageResults: [
                .failure(
                    .api(.unauthenticated)
                ),
            ]
        )
        let context = makeModel(loader: loader)

        await context.model.loadIfNeeded()

        #expect(
            context.model.authenticationFailure
                == .api(.unauthenticated)
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
    ) -> PipelineDetailModelContext {
        let account =
            PipelineDetailCurrentAccountBox()
        let model = GitLabPipelineDetailModel(
            accountID:
                GitLabAccountID(
                    host:
                        try! GitLabHost(
                            "gitlab.example.com"
                        ),
                    userID: 17
                ),
            route:
                GitLabPipelineRoute(
                    projectID: 42,
                    pipelineID: 501
                )!,
            cacheLifetime: .active,
            loader: loader,
            pollWaiter: pollWaiter,
            isAccountCurrent: {
                account.isCurrent
            }
        )
        return PipelineDetailModelContext(
            model: model,
            account: account
        )
    }

    private func pipeline(
        status: String
    ) throws -> GitLabPipeline {
        try decode(
            """
            {
              "id": 501,
              "project_id": 42,
              "sha": "abc123",
              "ref": "main",
              "status": "\(status)"
            }
            """
        )
    }

    private func job(
        id: Int = 800,
        name: String = "ios-tests",
        stage: String = "test",
        status: String
    ) throws -> GitLabPipelineJob {
        try decode(
            """
            {
              "id": \(id),
              "name": "\(name)",
              "stage": "\(stage)",
              "status": "\(status)",
              "pipeline": {
                "id": 501,
                "project_id": 42
              }
            }
            """
        )
    }

    private func triggerJob(
        id: Int = 801,
        name: String = "child",
        stage: String = "deploy",
        status: String
    ) throws -> GitLabPipelineTriggerJob {
        try decode(
            """
            {
              "id": \(id),
              "name": "\(name)",
              "stage": "\(stage)",
              "status": "\(status)",
              "pipeline": {
                "id": 501,
                "project_id": 42
              }
            }
            """
        )
    }

    private func pipelineEvent(
        _ pipeline: GitLabPipeline
    ) -> GitLabAPIResponseEvent<
        GitLabPipeline
    > {
        GitLabAPIResponseEvent(
            value: pipeline,
            metadata:
                GitLabResponseMetadata(),
            source: .network
        )
    }

    private func jobEvent(
        _ jobs: [GitLabPipelineJob],
        nextPageURL: URL? = nil
    ) -> GitLabResourcePageEvent<
        GitLabPipelineJob
    > {
        GitLabResourcePageEvent(
            page:
                GitLabResourcePage(
                    items: jobs,
                    nextPageURL:
                        nextPageURL
                ),
            source: .network
        )
    }

    private func triggerEvent(
        _ jobs:
            [GitLabPipelineTriggerJob]
    ) -> GitLabResourcePageEvent<
        GitLabPipelineTriggerJob
    > {
        GitLabResourcePageEvent(
            page:
                GitLabResourcePage(
                    items: jobs,
                    nextPageURL: nil
                ),
            source: .network
        )
    }

    private func decode<Value>(
        _ json: String
    ) throws -> Value
    where Value: Decodable & Sendable {
        try JSONDecoder().decode(
            Value.self,
            from: Data(json.utf8)
        )
    }
}

@MainActor
private struct PipelineDetailModelContext {
    let model: GitLabPipelineDetailModel
    let account:
        PipelineDetailCurrentAccountBox
}

@MainActor
private final class
    PipelineDetailCurrentAccountBox
{
    var isCurrent = true
}

private struct PipelineTriggerFirstPageResult:
    Sendable
{
    let event:
        GitLabResourcePageEvent<
            GitLabPipelineTriggerJob
        >
    let selectedCapability:
        GitLabPipelineTriggerJobsCapability
}

private actor PipelineDetailLoader:
    GitLabPipelineLoading
{
    private var pipelineResults:
        [
            Result<
                GitLabAPIResponseEvent<
                    GitLabPipeline
                >,
                GitLabSessionClientError
            >
        ]
    private var jobFirstPageResults:
        [
            Result<
                GitLabResourcePageEvent<
                    GitLabPipelineJob
                >,
                GitLabSessionClientError
            >
        ]
    private var jobNextPageResults:
        [
            URL:
                Result<
                    GitLabResourcePage<
                        GitLabPipelineJob
                    >,
                    GitLabSessionClientError
                >
        ]
    private var triggerFirstPageResults:
        [
            Result<
                PipelineTriggerFirstPageResult,
                GitLabSessionClientError
            >
        ]
    private var triggerCapabilities:
        [
            GitLabPipelineTriggerJobsCapability
        ] = []

    init(
        pipelineResults:
            [
                Result<
                    GitLabAPIResponseEvent<
                        GitLabPipeline
                    >,
                    GitLabSessionClientError
                >
            ],
        jobFirstPageResults:
            [
                Result<
                    GitLabResourcePageEvent<
                        GitLabPipelineJob
                    >,
                    GitLabSessionClientError
                >
            ],
        jobNextPageResults:
            [
                URL:
                    Result<
                        GitLabResourcePage<
                            GitLabPipelineJob
                        >,
                        GitLabSessionClientError
                    >
            ] = [:],
        triggerFirstPageResults:
            [
                Result<
                    PipelineTriggerFirstPageResult,
                    GitLabSessionClientError
                >
            ]
    ) {
        self.pipelineResults =
            pipelineResults
        self.jobFirstPageResults =
            jobFirstPageResults
        self.jobNextPageResults =
            jobNextPageResults
        self.triggerFirstPageResults =
            triggerFirstPageResults
    }

    func recordedTriggerCapabilities()
        -> [
            GitLabPipelineTriggerJobsCapability
        ]
    {
        triggerCapabilities
    }

    func loadMergeRequestPipelinesPage(
        at route: GitLabMergeRequestRoute,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabPipeline>
    {
        fatalError("Not used by detail model tests")
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
        fatalError("Not used by detail model tests")
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
        guard
            route.projectID == 42,
            route.pipelineID == 501,
            !pipelineResults.isEmpty
        else {
            throw .api(.invalidResponse)
        }
        await onResponse(
            try pipelineResults
                .removeFirst()
                .get()
        )
    }

    func loadPipelineJobsPage(
        at route: GitLabPipelineRoute,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabPipelineJob>
    {
        guard
            let nextPageURL,
            let result =
                jobNextPageResults
                .removeValue(
                    forKey: nextPageURL
                )
        else {
            throw .api(.invalidResponse)
        }
        return try result.get()
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
        guard
            !jobFirstPageResults.isEmpty
        else {
            throw .api(.invalidResponse)
        }
        await onPage(
            try jobFirstPageResults
                .removeFirst()
                .get()
        )
    }

    func loadPipelineTriggerJobsPage(
        at route: GitLabPipelineRoute,
        capability:
            GitLabPipelineTriggerJobsCapability,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineTriggerJobsPage
    {
        fatalError("No trigger pagination in these tests")
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
        guard
            !triggerFirstPageResults.isEmpty
        else {
            throw .api(.invalidResponse)
        }
        triggerCapabilities.append(
            capability
        )
        let result =
            try triggerFirstPageResults
            .removeFirst()
            .get()
        await onPage(result.event)
        return result.selectedCapability
    }
}
