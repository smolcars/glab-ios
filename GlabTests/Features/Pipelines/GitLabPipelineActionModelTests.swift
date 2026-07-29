import Foundation
import Testing
@testable import Glab

@Suite("GitLab pipeline action model")
@MainActor
struct GitLabPipelineActionModelTests {
    @Test("Exposes only status-valid actions")
    func exposesStatusValidActions() throws {
        let fixture = try fixture(
            pipelineStatus: "failed",
            jobStatus: "manual"
        )

        #expect(
            fixture.model
                .availablePipelineActions
                == [.retryPipeline]
        )
        #expect(
            fixture.model.availableJobActions(
                for: fixture.state.job
            ) == [.playJob]
        )

        fixture.state.pipeline =
            try pipeline(status: "running")
        fixture.state.job =
            try job(status: "running")

        #expect(
            fixture.model
                .availablePipelineActions
                == [.cancelPipeline]
        )
        #expect(
            fixture.model.availableJobActions(
                for: fixture.state.job
            ) == [.cancelJob]
        )
    }

    @Test("Read-only and replaced accounts expose no actions")
    func gatesUnavailableAccounts() throws {
        let readOnly = try fixture(
            apiAccess: .readOnly
        )
        let replaced = try fixture(
            isAccountCurrent: false
        )

        #expect(
            readOnly.model
                .availablePipelineActions
                .isEmpty
        )
        #expect(
            replaced.model
                .availablePipelineActions
                .isEmpty
        )
    }

    @Test("Confirmation rejects a stale status without sending")
    func rejectsStaleConfirmation() async throws {
        let fixture = try fixture(
            pipelineStatus: "failed"
        )
        fixture.model.request(
            .retryPipeline
        )
        fixture.state.pipeline =
            try pipeline(status: "success")

        await fixture.model.confirm()

        #expect(
            fixture.model.failure == .stale
        )
        #expect(
            await fixture.service.actions
                .isEmpty
        )
    }

    @Test("Confirmed pipeline retry reconciles and refreshes once")
    func retriesPipeline() async throws {
        let fixture = try fixture(
            pipelineStatus: "failed",
            responsePipelineStatus: "pending"
        )
        fixture.model.request(
            .retryPipeline
        )

        await fixture.model.confirm()

        #expect(
            await fixture.service.actions
                == [.retryPipeline]
        )
        #expect(
            fixture.state.pipeline.status
                .rawValue == "pending"
        )
        #expect(
            fixture.state.refreshCount == 1
        )
        #expect(fixture.model.failure == nil)
    }

    @Test("Confirmed job cancellation reconciles and removes only its trace")
    func cancelsJob() async throws {
        let fixture = try fixture(
            pipelineStatus: "running",
            jobStatus: "running",
            responseJobStatus: "canceled"
        )
        fixture.model.request(
            .cancelJob,
            job: fixture.state.job
        )

        await fixture.model.confirm()

        #expect(
            await fixture.service.actions
                == [.cancelJob]
        )
        #expect(
            fixture.state.job.status.rawValue
                == "canceled"
        )
        #expect(
            await fixture.traceStore
                .removedKeys
                == [
                    GitLabJobTraceKey(
                        accountID:
                            fixture.accountID,
                        route:
                            GitLabJobTraceRoute(
                                projectID: 42,
                                jobID: 800
                            )!
                    )
                ]
        )
        #expect(
            fixture.state.refreshCount == 1
        )
    }

    @Test(
        "Confirmed pipeline cancellation removes loaded nonterminal traces"
    )
    func cancelPipelineRemovesActiveTraces()
        async throws
    {
        let fixture = try fixture(
            pipelineStatus: "running",
            jobStatus: "running",
            responsePipelineStatus:
                "canceling"
        )
        fixture.model.request(
            .cancelPipeline
        )

        await fixture.model.confirm()

        #expect(
            await fixture.traceStore
                .removedKeys
                .map(\.route.jobID)
                == [800]
        )
    }

    @Test(
        "Unknown pipeline-cancel delivery removes the captured traces"
    )
    func uncertainPipelineCancelRemovesTraces()
        async throws
    {
        let fixture = try fixture(
            pipelineStatus: "running",
            jobStatus: "running",
            serviceError:
                .api(
                    .server(
                        statusCode: 503
                    )
                )
        )
        fixture.model.request(
            .cancelPipeline
        )

        await fixture.model.confirm()

        #expect(
            await fixture.traceStore
                .removedKeys
                .map(\.route.jobID)
                == [800]
        )
    }

    @Test(
        "Rejected pipeline cancellation preserves traces"
    )
    func rejectedPipelineCancelPreservesTraces()
        async throws
    {
        let fixture = try fixture(
            pipelineStatus: "running",
            jobStatus: "running",
            serviceError:
                .api(.forbidden)
        )
        fixture.model.request(
            .cancelPipeline
        )

        await fixture.model.confirm()

        #expect(
            await fixture.traceStore
                .removedKeys.isEmpty
        )
    }

    @Test(
        "Pipeline cancellation preserves terminal job traces"
    )
    func pipelineCancelPreservesTerminalTraces()
        async throws
    {
        let fixture = try fixture(
            pipelineStatus: "running",
            jobStatus: "success",
            responsePipelineStatus:
                "canceling"
        )
        fixture.model.request(
            .cancelPipeline
        )

        await fixture.model.confirm()

        #expect(
            await fixture.traceStore
                .removedKeys.isEmpty
        )
    }

    @Test(
        "Pipeline cancellation snapshots job traces when the POST begins"
    )
    func pipelineCancelRefreshesTraceSnapshot()
        async throws
    {
        let fixture = try fixture(
            pipelineStatus: "running",
            jobStatus: "running",
            responsePipelineStatus:
                "canceling"
        )
        fixture.model.request(
            .cancelPipeline
        )
        fixture.state.job =
            try job(status: "success")

        await fixture.model.confirm()

        #expect(
            await fixture.traceStore
                .removedKeys.isEmpty
        )
    }

    @Test("Unknown delivery refreshes and remains visibly uncertain")
    func preservesUnknownDelivery() async throws {
        let error =
            GitLabSessionClientError.api(
                .server(statusCode: 503)
            )
        let fixture = try fixture(
            pipelineStatus: "failed",
            serviceError: error
        )
        fixture.model.request(
            .retryPipeline
        )

        await fixture.model.confirm()

        #expect(
            fixture.model.failure
                == .mutation(
                    error,
                    .deliveryUnknown
                )
        )
        #expect(
            fixture.state.refreshCount == 1
        )
    }

    @Test("A pending confirmation is not replaced by rapid taps")
    func deduplicatesConfirmation() throws {
        let fixture = try fixture(
            pipelineStatus: "failed",
            jobStatus: "failed"
        )
        fixture.model.request(
            .retryPipeline
        )
        fixture.model.request(
            .retryJob,
            job: fixture.state.job
        )

        #expect(
            fixture.model.confirmation?
                .action == .retryPipeline
        )
    }

    private func fixture(
        pipelineStatus: String = "failed",
        jobStatus: String = "failed",
        responsePipelineStatus:
            String = "pending",
        responseJobStatus:
            String = "pending",
        apiAccess: GitLabAPIAccess = .readWrite,
        isAccountCurrent: Bool = true,
        serviceError:
            GitLabSessionClientError? = nil
    ) throws -> Fixture {
        let accountID =
            GitLabAccountID(
                host:
                    try GitLabHost(
                        "gitlab.example.com"
                    ),
                userID: 7
            )
        let state =
            PipelineActionState(
                pipeline:
                    try pipeline(
                        status: pipelineStatus
                    ),
                job:
                    try job(status: jobStatus)
            )
        let service =
            RecordingPipelineActionService(
                pipeline:
                    try pipeline(
                        status:
                            responsePipelineStatus
                    ),
                job:
                    try job(
                        status:
                            responseJobStatus
                    ),
                error: serviceError
            )
        let traceStore =
            RecordingGitLabJobTraceStore()
        let model =
            GitLabPipelineActionModel(
                accountID: accountID,
                route: pipelineRoute,
                apiAccess: apiAccess,
                service: service,
                traceStore: traceStore,
                isAccountCurrent: {
                    isAccountCurrent
                },
                currentPipeline: {
                    state.pipeline
                },
                currentJobs: {
                    [state.job]
                },
                reconcilePipeline: {
                    state.pipeline = $0
                },
                reconcileJob: {
                    state.job = $0
                },
                refresh: {
                    state.refreshCount += 1
                }
            )
        return Fixture(
            model: model,
            service: service,
            traceStore: traceStore,
            state: state,
            accountID: accountID
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

    private func pipeline(
        status: String
    ) throws -> GitLabPipeline {
        try JSONDecoder().decode(
            GitLabPipeline.self,
            from:
                Data(
                    """
                    {
                      "id": 501,
                      "project_id": 42,
                      "sha": "abc123",
                      "ref": "main",
                      "status": "\(status)"
                    }
                    """.utf8
                )
        )
    }

    private func job(
        status: String
    ) throws -> GitLabPipelineJob {
        try JSONDecoder().decode(
            GitLabPipelineJob.self,
            from:
                Data(
                    """
                    {
                      "id": 800,
                      "name": "ios-tests",
                      "stage": "test",
                      "status": "\(status)",
                      "pipeline": {
                        "id": 501,
                        "project_id": 42
                      }
                    }
                    """.utf8
                )
        )
    }

    private struct Fixture {
        let model: GitLabPipelineActionModel
        let service:
            RecordingPipelineActionService
        let traceStore:
            RecordingGitLabJobTraceStore
        let state: PipelineActionState
        let accountID: GitLabAccountID
    }
}

@MainActor
private final class PipelineActionState {
    var pipeline: GitLabPipeline
    var job: GitLabPipelineJob
    var refreshCount = 0

    init(
        pipeline: GitLabPipeline,
        job: GitLabPipelineJob
    ) {
        self.pipeline = pipeline
        self.job = job
    }
}

private actor RecordingPipelineActionService:
    GitLabPipelineActionServing
{
    private let pipeline: GitLabPipeline
    private let job: GitLabPipelineJob
    private let error:
        GitLabSessionClientError?
    private(set) var actions:
        [GitLabPipelineActionKind] = []

    init(
        pipeline: GitLabPipeline,
        job: GitLabPipelineJob,
        error:
            GitLabSessionClientError?
    ) {
        self.pipeline = pipeline
        self.job = job
        self.error = error
    }

    func retryPipeline(
        at route: GitLabPipelineRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        try record(.retryPipeline)
        return pipeline
    }

    func cancelPipeline(
        at route: GitLabPipelineRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        try record(.cancelPipeline)
        return pipeline
    }

    func retryJob(
        at route: GitLabJobRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        try record(.retryJob)
        return job
    }

    func cancelJob(
        at route: GitLabJobRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        try record(.cancelJob)
        return job
    }

    func playJob(
        at route: GitLabJobRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        try record(.playJob)
        return job
    }

    func createMergeRequestPipeline(
        at route: GitLabMergeRequestRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        throw .api(.invalidResponse)
    }

    private func record(
        _ action: GitLabPipelineActionKind
    ) throws(GitLabSessionClientError) {
        actions.append(action)
        if let error {
            throw error
        }
    }
}
