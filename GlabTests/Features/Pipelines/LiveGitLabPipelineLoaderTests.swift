import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab pipeline loader")
struct LiveGitLabPipelineLoaderTests {
    @Test("Loads pipeline history pages with active caching")
    func loadsPipelineHistory() async throws {
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/projects/42/merge_requests/7/pipelines?page=2"
            )
        )
        let client = RecordingPipelineClient(
            pipeline: try pipeline(),
            job: try job(),
            trigger: try trigger(),
            nextPageURL: nextPageURL
        )
        let loader = LiveGitLabPipelineLoader(
            client: client
        )
        let events = PipelinePageEventRecorder()

        try await loader
            .loadMergeRequestPipelinesFirstPage(
                at: mergeRequestRoute,
                refreshBehavior: .ifStale
            ) {
                await events.append($0)
            }
        let nextPage =
            try await loader
                .loadMergeRequestPipelinesPage(
                    at: mergeRequestRoute,
                    after: nextPageURL
                )

        #expect(
            await events.values.map(\.page.items)
                == [[try pipeline()]]
        )
        #expect(
            await events.values
                .map(\.page.nextPageURL)
                == [nextPageURL]
        )
        #expect(
            nextPage.items == [try pipeline()]
        )
        #expect(
            await client.cachePolicies
                == [.pipelineActive]
        )
        #expect(
            await client.refreshBehaviors
                == [.ifStale]
        )
        #expect(
            await client.pageDescriptions
                == [
                    "initial:projects/42/merge_requests/7/pipelines",
                    "next:\(nextPageURL.absoluteString)",
                ]
        )
    }

    @Test("Uses immutable active and completed cache lifetimes")
    func usesSelectedPipelineCacheLifetime()
        async throws
    {
        let client = RecordingPipelineClient(
            pipeline: try pipeline(),
            job: try job(),
            trigger: try trigger()
        )
        let loader = LiveGitLabPipelineLoader(
            client: client
        )
        let pipelineEvents =
            PipelineResponseEventRecorder()
        let jobEvents =
            PipelineJobPageEventRecorder()

        try await loader.loadPipeline(
            at: pipelineRoute,
            cacheLifetime: .completed,
            refreshBehavior: .ifStale
        ) {
            await pipelineEvents.append($0)
        }
        try await loader.loadPipelineJobsFirstPage(
            at: pipelineRoute,
            cacheLifetime: .active,
            refreshBehavior: .always
        ) {
            await jobEvents.append($0)
        }

        #expect(
            await pipelineEvents.values
                .map(\.value) == [try pipeline()]
        )
        #expect(
            await jobEvents.values
                .map(\.page.items) == [[try job()]]
        )
        #expect(
            await client.cachePolicies
                == [
                    .pipelineCompleted,
                    .pipelineActive,
                ]
        )
        #expect(
            GitLabResponseCachePolicy.pipelineActive
                == GitLabResponseCachePolicy(
                    freshFor: 15,
                    maximumAge: 60 * 60
                )
        )
        #expect(
            GitLabResponseCachePolicy.pipelineCompleted
                == GitLabResponseCachePolicy(
                    freshFor: 5 * 60,
                    maximumAge: 24 * 60 * 60
                )
        )
    }

    @Test("Loads ordinary and trigger job pages independently")
    func loadsJobAndTriggerPages() async throws {
        let client = RecordingPipelineClient(
            pipeline: try pipeline(),
            job: try job(),
            trigger: try trigger()
        )
        let loader = LiveGitLabPipelineLoader(
            client: client
        )
        let jobsNextURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/projects/42/pipelines/501/jobs?page=2"
            )
        )
        let triggersNextURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/projects/42/pipelines/501/trigger_jobs?page=2"
            )
        )

        let jobs =
            try await loader
                .loadPipelineJobsPage(
                    at: pipelineRoute,
                    after: nil
                )
        let moreJobs =
            try await loader
                .loadPipelineJobsPage(
                    at: pipelineRoute,
                    after: jobsNextURL
                )
        let triggers =
            try await loader
                .loadPipelineTriggerJobsPage(
                    at: pipelineRoute,
                    capability: .preferred,
                    after: nil
                )
        let moreTriggers =
            try await loader
                .loadPipelineTriggerJobsPage(
                    at: pipelineRoute,
                    capability:
                        triggers.capability,
                    after: triggersNextURL
                )

        #expect(jobs.items == [try job()])
        #expect(moreJobs.items == [try job()])
        #expect(
            triggers.page.items
                == [try trigger()]
        )
        #expect(
            moreTriggers.page.items
                == [try trigger()]
        )
        #expect(
            moreTriggers.capability
                == .preferred
        )
    }

    @Test("Falls back to bridges only after trigger_jobs returns 404")
    func fallsBackAndRemembersLegacyCapability()
        async throws
    {
        let client = RecordingPipelineClient(
            pipeline: try pipeline(),
            job: try job(),
            trigger: try trigger(),
            preferredTriggerFailure:
                .api(.notFound)
        )
        let loader = LiveGitLabPipelineLoader(
            client: client
        )
        let events =
            PipelineTriggerPageEventRecorder()

        let capability =
            try await loader
                .loadPipelineTriggerJobsFirstPage(
                    at: pipelineRoute,
                    capability: .preferred,
                    cacheLifetime: .active,
                    refreshBehavior: .ifStale
                ) {
                    await events.append($0)
                }
        let remembered =
            try await loader
                .loadPipelineTriggerJobsFirstPage(
                    at: pipelineRoute,
                    capability: capability,
                    cacheLifetime: .active,
                    refreshBehavior: .always
                ) { _ in }

        #expect(capability == .legacy)
        #expect(remembered == .legacy)
        #expect(
            await events.values
                .map(\.page.items)
                == [[try trigger()]]
        )
        #expect(
            await client.initialPaths
                == [
                    pipelinePath
                        + ["trigger_jobs"],
                    pipelinePath + ["bridges"],
                    pipelinePath + ["bridges"],
                ]
        )
    }

    @Test(
        "Does not use legacy trigger jobs for non-404 failures",
        arguments: [
            GitLabSessionClientError
                .api(.unauthenticated),
            GitLabSessionClientError
                .api(.forbidden),
            GitLabSessionClientError
                .api(.server(statusCode: 503)),
            GitLabSessionClientError
                .api(.decoding),
            GitLabSessionClientError
                .api(.cancelled),
        ]
    )
    func preservesPreferredTriggerFailure(
        failure: GitLabSessionClientError
    ) async throws {
        let client = RecordingPipelineClient(
            pipeline: try pipeline(),
            job: try job(),
            trigger: try trigger(),
            preferredTriggerFailure: failure
        )
        let loader = LiveGitLabPipelineLoader(
            client: client
        )

        await #expect(throws: failure) {
            _ = try await loader
                .loadPipelineTriggerJobsFirstPage(
                    at: pipelineRoute,
                    capability: .preferred,
                    cacheLifetime: .active,
                    refreshBehavior: .always
                ) { _ in }
        }
        #expect(
            await client.initialPaths
                == [
                    pipelinePath
                        + ["trigger_jobs"],
                ]
        )
    }

    @Test("Rejects mismatched pipeline and job responses")
    func rejectsRouteMismatches() async throws {
        let mismatchedPipeline =
            try pipeline(
                id: 999,
                projectID: 42
            )
        let mismatchedJob =
            try job(
                pipelineID: 999,
                projectID: 42
            )
        let client = RecordingPipelineClient(
            pipeline: mismatchedPipeline,
            job: mismatchedJob,
            trigger: try trigger()
        )
        let loader = LiveGitLabPipelineLoader(
            client: client
        )

        await #expect(
            throws:
                GitLabSessionClientError
                .api(.invalidResponse)
        ) {
            try await loader.loadPipeline(
                at: pipelineRoute,
                cacheLifetime: .active,
                refreshBehavior: .always
            ) { _ in }
        }
        await #expect(
            throws:
                GitLabSessionClientError
                .api(.invalidResponse)
        ) {
            try await loader
                .loadPipelineJobsFirstPage(
                    at: pipelineRoute,
                    cacheLifetime: .active,
                    refreshBehavior: .always
                ) { _ in }
        }
    }

    private var mergeRequestRoute:
        GitLabMergeRequestRoute
    {
        GitLabMergeRequestRoute(
            projectID: 42,
            mergeRequestIID: 7
        )
    }

    private var pipelineRoute:
        GitLabPipelineRoute
    {
        GitLabPipelineRoute(
            projectID: 42,
            pipelineID: 501
        )!
    }

    private var pipelinePath: [String] {
        [
            "projects",
            "42",
            "pipelines",
            "501",
        ]
    }

    private func pipeline(
        id: Int = 501,
        projectID: Int = 42
    ) throws -> GitLabPipeline {
        try decode(
            """
            {
              "id": \(id),
              "project_id": \(projectID),
              "sha": "abc123",
              "ref": "main",
              "status": "running"
            }
            """
        )
    }

    private func job(
        pipelineID: Int = 501,
        projectID: Int = 42
    ) throws -> GitLabPipelineJob {
        try decode(
            """
            {
              "id": 800,
              "name": "ios-tests",
              "stage": "test",
              "status": "running",
              "pipeline": {
                "id": \(pipelineID),
                "project_id": \(projectID)
              }
            }
            """
        )
    }

    private func trigger()
        throws -> GitLabPipelineTriggerJob
    {
        try decode(
            """
            {
              "id": 801,
              "name": "child",
              "stage": "test",
              "status": "pending",
              "pipeline": {
                "id": 501,
                "project_id": 42
              }
            }
            """
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

private actor RecordingPipelineClient:
    GitLabPaginatedSessionRequestSending
{
    let pipeline: GitLabPipeline
    let job: GitLabPipelineJob
    let trigger: GitLabPipelineTriggerJob
    let nextPageURL: URL?
    let preferredTriggerFailure:
        GitLabSessionClientError?
    private(set) var initialPaths:
        [[String]] = []
    private(set) var pageDescriptions:
        [String] = []
    private(set) var cachePolicies:
        [GitLabResponseCachePolicy] = []
    private(set) var refreshBehaviors:
        [GitLabCacheRefreshBehavior] = []

    init(
        pipeline: GitLabPipeline,
        job: GitLabPipelineJob,
        trigger: GitLabPipelineTriggerJob,
        nextPageURL: URL? = nil,
        preferredTriggerFailure:
            GitLabSessionClientError? = nil
    ) {
        self.pipeline = pipeline
        self.job = job
        self.trigger = trigger
        self.nextPageURL = nextPageURL
        self.preferredTriggerFailure =
            preferredTriggerFailure
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        initialPaths.append(
            endpoint.pathComponents
        )
        return pipeline as! Response
    }

    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> GitLabAPIResponse<Response>
    {
        switch page {
        case let .initial(endpoint):
            initialPaths.append(
                endpoint.pathComponents
            )
            pageDescriptions.append(
                "initial:"
                    + endpoint.pathComponents
                        .joined(separator: "/")
            )
            if
                endpoint.pathComponents.last
                    == "trigger_jobs",
                let preferredTriggerFailure
            {
                throw preferredTriggerFailure
            }
            return try response(
                for: endpoint.pathComponents
            )
        case let .next(url):
            pageDescriptions.append(
                "next:\(url.absoluteString)"
            )
            let value: Any =
                if url.path.hasSuffix("/jobs") {
                    [job]
                } else if
                    url.path.hasSuffix(
                        "/trigger_jobs"
                    )
                {
                    [trigger]
                } else {
                    [pipeline]
                }
            guard
                let response =
                    value as? Response
            else {
                throw .api(.invalidResponse)
            }
            return GitLabAPIResponse(
                value: response,
                metadata:
                    GitLabResponseMetadata()
            )
        }
    }

    func loadPage<Response>(
        _ page: GitLabAPIPageRequest<Response>,
        cachePolicy: GitLabResponseCachePolicy,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<Response>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        cachePolicies.append(cachePolicy)
        refreshBehaviors.append(
            refreshBehavior
        )
        let response = try await sendPage(page)
        await onResponse(
            GitLabAPIResponseEvent(
                value: response.value,
                metadata: response.metadata,
                source: .network
            )
        )
    }

    func loadResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>,
        cachePolicy: GitLabResponseCachePolicy,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<Response>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        cachePolicies.append(cachePolicy)
        refreshBehaviors.append(
            refreshBehavior
        )
        initialPaths.append(
            endpoint.pathComponents
        )
        await onResponse(
            GitLabAPIResponseEvent(
                value: pipeline as! Response,
                metadata:
                    GitLabResponseMetadata(),
                source: .network
            )
        )
    }

    private func response<Response>(
        for path: [String]
    ) throws(GitLabSessionClientError)
        -> GitLabAPIResponse<Response>
    {
        let value: Any =
            switch path.last {
            case "jobs":
                [job]
            case "trigger_jobs", "bridges":
                [trigger]
            default:
                [pipeline]
            }

        guard let response = value as? Response else {
            throw .api(.invalidResponse)
        }
        return GitLabAPIResponse(
            value: response,
            metadata:
                GitLabResponseMetadata(
                    nextPageURL: nextPageURL
                )
        )
    }
}

private actor PipelinePageEventRecorder {
    private(set) var values:
        [
            GitLabResourcePageEvent<
                GitLabPipeline
            >
        ] = []

    func append(
        _ event:
            GitLabResourcePageEvent<
                GitLabPipeline
            >
    ) {
        values.append(event)
    }
}

private actor PipelineResponseEventRecorder {
    private(set) var values:
        [
            GitLabAPIResponseEvent<
                GitLabPipeline
            >
        ] = []

    func append(
        _ event:
            GitLabAPIResponseEvent<
                GitLabPipeline
            >
    ) {
        values.append(event)
    }
}

private actor PipelineJobPageEventRecorder {
    private(set) var values:
        [
            GitLabResourcePageEvent<
                GitLabPipelineJob
            >
        ] = []

    func append(
        _ event:
            GitLabResourcePageEvent<
                GitLabPipelineJob
            >
    ) {
        values.append(event)
    }
}

private actor PipelineTriggerPageEventRecorder {
    private(set) var values:
        [
            GitLabResourcePageEvent<
                GitLabPipelineTriggerJob
            >
        ] = []

    func append(
        _ event:
            GitLabResourcePageEvent<
                GitLabPipelineTriggerJob
            >
    ) {
        values.append(event)
    }
}
