import Foundation

nonisolated protocol GitLabPipelineActionServing:
    Sendable
{
    func retryPipeline(
        at route: GitLabPipelineRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipeline

    func cancelPipeline(
        at route: GitLabPipelineRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipeline

    func retryJob(
        at route: GitLabJobRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineJob

    func cancelJob(
        at route: GitLabJobRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineJob

    func playJob(
        at route: GitLabJobRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineJob

    func createMergeRequestPipeline(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipeline
}

nonisolated struct
    LiveGitLabPipelineActionService:
    GitLabPipelineActionServing,
    Sendable
{
    private let client:
        any GitLabSessionRequestSending

    init(
        client:
            any GitLabSessionRequestSending
    ) {
        self.client = client
    }

    @concurrent
    func retryPipeline(
        at route: GitLabPipelineRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        try await sendPipelineMutation(
            GitLabPipelineEndpoints
                .retryPipeline(at: route),
            route: route
        )
    }

    @concurrent
    func cancelPipeline(
        at route: GitLabPipelineRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        try await sendPipelineMutation(
            GitLabPipelineEndpoints
                .cancelPipeline(at: route),
            route: route
        )
    }

    @concurrent
    func retryJob(
        at route: GitLabJobRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        try await sendJobMutation(
            GitLabPipelineEndpoints
                .retryJob(at: route),
            route: route,
            requiresSameJobID: false
        )
    }

    @concurrent
    func cancelJob(
        at route: GitLabJobRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        try await sendJobMutation(
            GitLabPipelineEndpoints
                .cancelJob(at: route),
            route: route,
            requiresSameJobID: true
        )
    }

    @concurrent
    func playJob(
        at route: GitLabJobRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        try await sendJobMutation(
            GitLabPipelineEndpoints
                .playJob(at: route),
            route: route,
            requiresSameJobID: true
        )
    }

    @concurrent
    func createMergeRequestPipeline(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        guard
            let endpoint =
                GitLabPipelineEndpoints
                .createMergeRequestPipeline(
                    at: route
                )
        else {
            throw .api(.invalidResponse)
        }

        return try await sendMutation(
            endpoint,
            validates: {
                $0.projectID == nil
                    || $0.projectID
                        == route.projectID
            },
            invalidate: {
                await invalidateMergeRequestPipelines(
                    at: route
                )
            }
        )
    }
}

private nonisolated extension
    LiveGitLabPipelineActionService
{
    @concurrent
    func sendPipelineMutation(
        _ endpoint:
            GitLabAPIRequest<
                GitLabPipeline
            >,
        route: GitLabPipelineRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        try await sendMutation(
            endpoint,
            validates: {
                $0.id == route.pipelineID
                    && (
                        $0.projectID == nil
                            || $0.projectID
                                == route.projectID
                    )
            },
            invalidate: {
                await invalidatePipelineReads(
                    at: route
                )
            }
        )
    }

    @concurrent
    func sendJobMutation(
        _ endpoint:
            GitLabAPIRequest<
                GitLabPipelineJob
            >,
        route: GitLabJobRoute,
        requiresSameJobID: Bool
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        try await sendMutation(
            endpoint,
            validates: { job in
                (
                    !requiresSameJobID
                        || job.id == route.jobID
                )
                    && Self.job(
                        job,
                        matches: route
                    )
            },
            invalidate: {
                await invalidateJobReads(
                    at: route.pipelineRoute
                )
            }
        )
    }

    @concurrent
    func sendMutation<Response>(
        _ endpoint:
            GitLabAPIRequest<Response>,
        validates:
            @escaping @Sendable (
                Response
            ) -> Bool,
        invalidate:
            @escaping @Sendable () async -> Void
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        do {
            let response =
                try await client.send(
                    endpoint
                )
            guard validates(response) else {
                throw GitLabSessionClientError
                    .api(.invalidResponse)
            }
            await invalidate()
            return response
        } catch {
            let sessionError =
                error
                    as? GitLabSessionClientError
                ?? .api(.transport)
            if
                sessionError
                    .mutationDeliveryCertainty
                    == .deliveryUnknown
            {
                await invalidate()
            }
            throw sessionError
        }
    }

    @concurrent
    func invalidatePipelineReads(
        at route: GitLabPipelineRoute
    ) async {
        await client.invalidateCachedResponse(
            GitLabPipelineEndpoints
                .pipeline(at: route)
        )
        await client.invalidateCachedResponse(
            GitLabPipelineEndpoints
                .jobs(at: route)
        )
        await client.invalidateCachedResponse(
            GitLabPipelineEndpoints
                .triggerJobs(at: route)
        )
        await client.invalidateCachedResponse(
            GitLabPipelineEndpoints
                .legacyTriggerJobs(at: route)
        )
    }

    @concurrent
    func invalidateJobReads(
        at route: GitLabPipelineRoute
    ) async {
        await client.invalidateCachedResponse(
            GitLabPipelineEndpoints
                .pipeline(at: route)
        )
        await client.invalidateCachedResponse(
            GitLabPipelineEndpoints
                .jobs(at: route)
        )
    }

    @concurrent
    func invalidateMergeRequestPipelines(
        at route: GitLabMergeRequestRoute
    ) async {
        guard
            let endpoint =
                GitLabPipelineEndpoints
                .mergeRequestPipelines(
                    at: route
                )
        else {
            return
        }
        await client.invalidateCachedResponse(
            endpoint
        )
    }

    static func job(
        _ job: GitLabPipelineJob,
        matches route: GitLabJobRoute
    ) -> Bool {
        guard let pipeline = job.pipeline else {
            return true
        }
        return pipeline.id == route.pipelineID
            && (
                pipeline.projectID == nil
                    || pipeline.projectID
                        == route.projectID
            )
    }
}
