import Foundation

nonisolated enum GitLabPipelineCacheLifetime:
    Equatable,
    Sendable
{
    case active
    case completed

    var policy: GitLabResponseCachePolicy {
        switch self {
        case .active:
            .pipelineActive
        case .completed:
            .pipelineCompleted
        }
    }
}

nonisolated enum GitLabPipelineTriggerJobsCapability:
    Equatable,
    Sendable
{
    case preferred
    case legacy
}

nonisolated struct GitLabPipelineTriggerJobsPage:
    Sendable
{
    let page:
        GitLabResourcePage<
            GitLabPipelineTriggerJob
        >
    let capability:
        GitLabPipelineTriggerJobsCapability
}

nonisolated protocol GitLabPipelineLoading:
    Sendable
{
    func loadMergeRequestPipelinesPage(
        at route: GitLabMergeRequestRoute,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabPipeline>

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
    ) async throws(GitLabSessionClientError)

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
    ) async throws(GitLabSessionClientError)

    func loadPipelineJobsPage(
        at route: GitLabPipelineRoute,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabPipelineJob>

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
    ) async throws(GitLabSessionClientError)

    func loadPipelineTriggerJobsPage(
        at route: GitLabPipelineRoute,
        capability:
            GitLabPipelineTriggerJobsCapability,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineTriggerJobsPage

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
}

nonisolated struct LiveGitLabPipelineLoader:
    GitLabPipelineLoading,
    Sendable
{
    private let client:
        any GitLabPaginatedSessionRequestSending

    init(
        client:
            any GitLabPaginatedSessionRequestSending
    ) {
        self.client = client
    }

    @concurrent
    func loadMergeRequestPipelinesPage(
        at route: GitLabMergeRequestRoute,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabPipeline>
    {
        let request:
            GitLabAPIPageRequest<[GitLabPipeline]>
        if let nextPageURL {
            request = .next(nextPageURL)
        } else {
            guard
                let endpoint =
                    GitLabPipelineEndpoints
                    .mergeRequestPipelines(
                        at: route
                    )
            else {
                throw .api(.invalidResponse)
            }
            request = .initial(endpoint)
        }

        let response = try await client.sendPage(
            request
        )
        guard
            Self.pipelines(
                response.value,
                belongToProject:
                    route.projectID
            )
        else {
            throw .api(.invalidResponse)
        }
        return GitLabResourcePage(
            items: response.value,
            nextPageURL:
                response.metadata.nextPageURL,
            totalCount:
                response.metadata.totalCount
        )
    }

    @concurrent
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
            let endpoint =
                GitLabPipelineEndpoints
                .mergeRequestPipelines(at: route)
        else {
            throw .api(.invalidResponse)
        }
        let validation =
            PipelineResponseValidation()

        try await client.loadPage(
            .initial(endpoint),
            cachePolicy: .pipelineActive,
            refreshBehavior: refreshBehavior
        ) { event in
            guard
                Self.pipelines(
                    event.value,
                    belongToProject:
                        route.projectID
                )
            else {
                await validation.reject()
                return
            }
            await onPage(
                GitLabResourcePageEvent(
                    apiResponse: event
                )
            )
        }
        guard await validation.isValid else {
            throw .api(.invalidResponse)
        }
    }

    @concurrent
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
        let validation =
            PipelineResponseValidation()

        try await client.loadResponse(
            GitLabPipelineEndpoints.pipeline(
                at: route
            ),
            cachePolicy: cacheLifetime.policy,
            refreshBehavior: refreshBehavior
        ) { event in
            guard
                Self.pipeline(
                    event.value,
                    matches: route
                )
            else {
                await validation.reject()
                return
            }
            await onResponse(event)
        }
        guard await validation.isValid else {
            throw .api(.invalidResponse)
        }
    }

    @concurrent
    func loadPipelineJobsPage(
        at route: GitLabPipelineRoute,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabPipelineJob>
    {
        let request:
            GitLabAPIPageRequest<
                [GitLabPipelineJob]
            > =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(
                    GitLabPipelineEndpoints.jobs(
                        at: route
                    )
                )
            }
        let response = try await client.sendPage(
            request
        )
        guard
            Self.jobs(
                response.value,
                match: route
            )
        else {
            throw .api(.invalidResponse)
        }
        return GitLabResourcePage(
            items: response.value,
            nextPageURL:
                response.metadata.nextPageURL,
            totalCount:
                response.metadata.totalCount
        )
    }

    @concurrent
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
        let validation =
            PipelineResponseValidation()

        try await client.loadPage(
            .initial(
                GitLabPipelineEndpoints.jobs(
                    at: route
                )
            ),
            cachePolicy: cacheLifetime.policy,
            refreshBehavior: refreshBehavior
        ) { event in
            guard
                Self.jobs(
                    event.value,
                    match: route
                )
            else {
                await validation.reject()
                return
            }
            await onPage(
                GitLabResourcePageEvent(
                    apiResponse: event
                )
            )
        }
        guard await validation.isValid else {
            throw .api(.invalidResponse)
        }
    }

    @concurrent
    func loadPipelineTriggerJobsPage(
        at route: GitLabPipelineRoute,
        capability:
            GitLabPipelineTriggerJobsCapability,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineTriggerJobsPage
    {
        if let nextPageURL {
            let response:
                GitLabAPIResponse<
                    [GitLabPipelineTriggerJob]
                > =
                try await client.sendPage(
                    .next(nextPageURL)
                )
            return try Self.triggerJobsPage(
                response,
                route: route,
                capability: capability
            )
        }

        do {
            return try await loadInitialTriggerJobsPage(
                at: route,
                capability: capability
            )
        } catch
            GitLabSessionClientError.api(.notFound)
            where capability == .preferred
        {
            return try await loadInitialTriggerJobsPage(
                at: route,
                capability: .legacy
            )
        }
    }

    @concurrent
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
        do {
            try await loadInitialTriggerJobsFirstPage(
                at: route,
                capability: capability,
                cacheLifetime: cacheLifetime,
                refreshBehavior:
                    refreshBehavior,
                onPage: onPage
            )
            return capability
        } catch
            GitLabSessionClientError.api(.notFound)
            where capability == .preferred
        {
            try await loadInitialTriggerJobsFirstPage(
                at: route,
                capability: .legacy,
                cacheLifetime: cacheLifetime,
                refreshBehavior:
                    refreshBehavior,
                onPage: onPage
            )
            return .legacy
        }
    }

    @concurrent
    private func loadInitialTriggerJobsPage(
        at route: GitLabPipelineRoute,
        capability:
            GitLabPipelineTriggerJobsCapability
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineTriggerJobsPage
    {
        let response:
            GitLabAPIResponse<
                [GitLabPipelineTriggerJob]
            > =
            try await client.sendPage(
                .initial(
                    Self.triggerJobsEndpoint(
                        at: route,
                        capability: capability
                    )
                )
            )
        return try Self.triggerJobsPage(
            response,
            route: route,
            capability: capability
        )
    }

    @concurrent
    private func loadInitialTriggerJobsFirstPage(
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
    ) async throws(GitLabSessionClientError) {
        let validation =
            PipelineResponseValidation()

        try await client.loadPage(
            .initial(
                Self.triggerJobsEndpoint(
                    at: route,
                    capability: capability
                )
            ),
            cachePolicy: cacheLifetime.policy,
            refreshBehavior: refreshBehavior
        ) { event in
            guard
                Self.triggerJobs(
                    event.value,
                    match: route
                )
            else {
                await validation.reject()
                return
            }
            await onPage(
                GitLabResourcePageEvent(
                    apiResponse: event
                )
            )
        }
        guard await validation.isValid else {
            throw .api(.invalidResponse)
        }
    }

    private static func triggerJobsEndpoint(
        at route: GitLabPipelineRoute,
        capability:
            GitLabPipelineTriggerJobsCapability
    ) -> GitLabAPIRequest<
        [GitLabPipelineTriggerJob]
    > {
        switch capability {
        case .preferred:
            GitLabPipelineEndpoints.triggerJobs(
                at: route
            )
        case .legacy:
            GitLabPipelineEndpoints
                .legacyTriggerJobs(at: route)
        }
    }

    private static func triggerJobsPage(
        _ response:
            GitLabAPIResponse<
                [GitLabPipelineTriggerJob]
            >,
        route: GitLabPipelineRoute,
        capability:
            GitLabPipelineTriggerJobsCapability
    ) throws(GitLabSessionClientError)
        -> GitLabPipelineTriggerJobsPage
    {
        guard
            triggerJobs(
                response.value,
                match: route
            )
        else {
            throw .api(.invalidResponse)
        }
        return GitLabPipelineTriggerJobsPage(
            page:
                GitLabResourcePage(
                    items: response.value,
                    nextPageURL:
                        response.metadata.nextPageURL,
                    totalCount:
                        response.metadata.totalCount
                ),
            capability: capability
        )
    }

    private static func pipelines(
        _ pipelines: [GitLabPipeline],
        belongToProject projectID: Int
    ) -> Bool {
        pipelines.allSatisfy {
            $0.projectID == nil
                || $0.projectID == projectID
        }
    }

    private static func pipeline(
        _ pipeline: GitLabPipeline,
        matches route: GitLabPipelineRoute
    ) -> Bool {
        pipeline.id == route.pipelineID
            && (
                pipeline.projectID == nil
                    || pipeline.projectID
                        == route.projectID
            )
    }

    private static func jobs(
        _ jobs: [GitLabPipelineJob],
        match route: GitLabPipelineRoute
    ) -> Bool {
        jobs.allSatisfy {
            pipelineReference(
                $0.pipeline,
                matches: route
            )
        }
    }

    private static func triggerJobs(
        _ jobs: [GitLabPipelineTriggerJob],
        match route: GitLabPipelineRoute
    ) -> Bool {
        jobs.allSatisfy {
            pipelineReference(
                $0.pipeline,
                matches: route
            )
        }
    }

    private static func pipelineReference(
        _ pipeline: GitLabPipelineReference?,
        matches route: GitLabPipelineRoute
    ) -> Bool {
        guard let pipeline else {
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

private actor PipelineResponseValidation {
    private(set) var isValid = true

    func reject() {
        isValid = false
    }
}
