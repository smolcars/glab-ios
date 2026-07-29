import Foundation
import Observation

private actor GitLabPipelineTriggerCapabilityStore {
    private var capability =
        GitLabPipelineTriggerJobsCapability.preferred

    func current()
        -> GitLabPipelineTriggerJobsCapability
    {
        capability
    }

    func select(
        _ capability:
            GitLabPipelineTriggerJobsCapability
    ) {
        self.capability = capability
    }
}

@MainActor
@Observable
final class GitLabPipelineDetailModel {
    let accountID: GitLabAccountID
    let route: GitLabPipelineRoute
    let jobs:
        GitLabPaginatedResourceModel<
            GitLabPipelineJob,
            Int
        >
    let triggerJobs:
        GitLabPaginatedResourceModel<
            GitLabPipelineTriggerJob,
            Int
        >

    private(set) var pipelineState =
        GitLabResourceDetailState<
            GitLabPipeline
        >.idle
    private(set) var pipelineRefreshError:
        GitLabSessionClientError?
    private(set) var pipelineSource:
        GitLabAPIResponseSource?
    private(set) var pipelineCacheStoredAt: Date?
    private(set) var stages:
        [GitLabPipelineStage] = []
    private(set) var isProjectingStages = false

    @ObservationIgnored
    private let loader:
        any GitLabPipelineLoading
    @ObservationIgnored
    private let cacheLifetime:
        GitLabPipelineCacheLifetime
    @ObservationIgnored
    private let accountScope:
        GitLabPipelineAccountScope
    @ObservationIgnored
    private let triggerCapabilityStore =
        GitLabPipelineTriggerCapabilityStore()
    @ObservationIgnored
    private let pollWaiter:
        GitLabPipelinePollWaiter
    @ObservationIgnored
    private var pipelineGeneration:
        UInt64 = 0
    @ObservationIgnored
    private var projectionGeneration:
        UInt64 = 0
    @ObservationIgnored
    private var isLoadingPipeline = false

    init(
        accountID: GitLabAccountID,
        route: GitLabPipelineRoute,
        cacheLifetime:
            GitLabPipelineCacheLifetime,
        loader: any GitLabPipelineLoading,
        pollWaiter:
            @escaping GitLabPipelinePollWaiter = {
                try await Task.sleep(
                    for: .seconds(15)
                )
            },
        isAccountCurrent:
            @escaping @MainActor () -> Bool
    ) {
        let accountScope =
            GitLabPipelineAccountScope(
                isCurrent: isAccountCurrent
            )
        self.accountID = accountID
        self.route = route
        self.cacheLifetime = cacheLifetime
        self.loader = loader
        self.pollWaiter = pollWaiter
        self.accountScope = accountScope
        jobs = Self.makeJobsModel(
            route: route,
            cacheLifetime: cacheLifetime,
            loader: loader,
            accountScope: accountScope
        )
        triggerJobs =
            Self.makeTriggerJobsModel(
                route: route,
                cacheLifetime: cacheLifetime,
                loader: loader,
                accountScope: accountScope,
                capabilityStore:
                    triggerCapabilityStore
            )
    }

    var pipeline: GitLabPipeline? {
        guard
            case let .loaded(pipeline) =
                pipelineState
        else {
            return nil
        }
        return pipeline
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        if
            pipelineRefreshError?
                .requiresReauthentication == true
        {
            return pipelineRefreshError
        }
        if
            case let .failed(error) =
                pipelineState,
            error.requiresReauthentication
        {
            return error
        }
        return jobs.authenticationFailure
            ?? triggerJobs.authenticationFailure
    }

    var hasActivelyChangingContent: Bool {
        pipeline?.status.isActivelyChanging
            == true
            || jobs.items.contains {
                $0.status.isActivelyChanging
            }
            || triggerJobs.items.contains {
                $0.status.isActivelyChanging
            }
    }

    var isRefreshing: Bool {
        isLoadingPipeline
            || jobs.isRefreshing
            || jobs.isLoadingInitial
            || triggerJobs.isRefreshing
            || triggerJobs.isLoadingInitial
    }

    func loadIfNeeded() async {
        guard accountScope.check() else {
            return
        }

        async let pipelineLoad: Void =
            loadPipelineIfNeeded()
        async let jobsLoad: Void =
            jobs.loadIfNeeded()
        async let triggerJobsLoad: Void =
            triggerJobs.loadIfNeeded()
        _ = await (
            pipelineLoad,
            jobsLoad,
            triggerJobsLoad
        )
        await projectStages()
    }

    func refresh() async {
        guard accountScope.check() else {
            return
        }

        async let pipelineLoad: Void =
            loadPipeline(
                refreshBehavior: .always
            )
        async let jobsLoad: Void =
            jobs.refresh()
        async let triggerJobsLoad: Void =
            triggerJobs.refresh()
        _ = await (
            pipelineLoad,
            jobsLoad,
            triggerJobsLoad
        )
        await projectStages()
    }

    func loadNextJobsPageIfNeeded(
        after job: GitLabPipelineJob
    ) async {
        guard accountScope.check() else {
            return
        }
        await jobs.loadNextPageIfNeeded(
            after: job
        )
        await projectStages()
    }

    func retryJobsNextPage() async {
        guard accountScope.check() else {
            return
        }
        await jobs.retryNextPage()
        await projectStages()
    }

    func loadNextTriggerJobsPageIfNeeded(
        after job: GitLabPipelineTriggerJob
    ) async {
        guard accountScope.check() else {
            return
        }
        await triggerJobs.loadNextPageIfNeeded(
            after: job
        )
        await projectStages()
    }

    func retryTriggerJobsNextPage() async {
        guard accountScope.check() else {
            return
        }
        await triggerJobs.retryNextPage()
        await projectStages()
    }

    func reconcileActionPipeline(
        _ pipeline: GitLabPipeline
    ) {
        guard
            accountScope.check(),
            pipeline.id == route.pipelineID,
            pipeline.projectID == nil
                || pipeline.projectID
                    == route.projectID
        else {
            return
        }
        pipelineGeneration &+= 1
        pipelineState = .loaded(pipeline)
        pipelineRefreshError = nil
        pipelineSource = .network
        pipelineCacheStoredAt = nil
    }

    func reconcileActionJob(
        _ job: GitLabPipelineJob
    ) async {
        guard
            accountScope.check(),
            Self.job(
                job,
                belongsTo: route
            )
        else {
            return
        }
        jobs.reconcileItem(
            job,
            countAdjustmentIfInserted: 1,
            keepsAtEndUntilLoaded: true
        )
        await projectStages()
    }

    func runVisible(
        isSceneActive: Bool
    ) async {
        guard
            isSceneActive,
            accountScope.check()
        else {
            return
        }

        await withTaskGroup(
            of: Void.self
        ) { group in
            group.addTask {
                await self
                    .observeStageRevisions()
            }
            group.addTask {
                await self.loadAndPoll(
                    isSceneActive:
                        isSceneActive
                )
            }

            await group.next()
            group.cancelAll()
        }
    }

    private func loadAndPoll(
        isSceneActive: Bool
    ) async {
        await loadIfNeeded()

        while shouldPoll(
            isSceneActive: isSceneActive
        ) {
            do {
                try await pollWaiter()
                try Task.checkCancellation()
            } catch {
                return
            }

            guard shouldPoll(
                isSceneActive: isSceneActive
            ) else {
                return
            }
            await refresh()
        }
    }

    private func shouldPoll(
        isSceneActive: Bool
    ) -> Bool {
        isSceneActive
            && !Task.isCancelled
            && accountScope.check()
            && authenticationFailure == nil
            && hasActivelyChangingContent
    }

    private func loadPipelineIfNeeded() async {
        guard pipelineState == .idle else {
            return
        }
        await loadPipeline(
            refreshBehavior: .ifStale
        )
    }

    private func loadPipeline(
        refreshBehavior:
            GitLabCacheRefreshBehavior
    ) async {
        guard
            accountScope.check(),
            !isLoadingPipeline
        else {
            return
        }

        pipelineGeneration &+= 1
        let generation =
            pipelineGeneration
        let previousState = pipelineState
        let previousRefreshError =
            pipelineRefreshError
        let previousSource = pipelineSource
        let previousCacheStoredAt =
            pipelineCacheStoredAt
        if pipeline == nil {
            pipelineState = .loading
        }
        pipelineRefreshError = nil
        isLoadingPipeline = true

        defer {
            if
                pipelineGeneration
                    == generation
            {
                isLoadingPipeline = false
            }
        }

        do {
            try await loader.loadPipeline(
                at: route,
                cacheLifetime: cacheLifetime,
                refreshBehavior:
                    refreshBehavior
            ) { [weak self] event in
                await self?.applyPipeline(
                    event,
                    generation: generation
                )
            }

            guard
                !Task.isCancelled,
                accountScope.check(),
                pipelineGeneration
                    == generation
            else {
                restorePipelineState(
                    state: previousState,
                    refreshError:
                        previousRefreshError,
                    source: previousSource,
                    cacheStoredAt:
                        previousCacheStoredAt,
                    generation: generation
                )
                return
            }
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled),
                accountScope.check(),
                pipelineGeneration
                    == generation
            else {
                restorePipelineState(
                    state: previousState,
                    refreshError:
                        previousRefreshError,
                    source: previousSource,
                    cacheStoredAt:
                        previousCacheStoredAt,
                    generation: generation
                )
                return
            }

            if pipeline == nil {
                pipelineState =
                    .failed(error)
            } else {
                pipelineRefreshError = error
            }
        }
    }

    private func applyPipeline(
        _ event:
            GitLabAPIResponseEvent<
                GitLabPipeline
            >,
        generation: UInt64
    ) {
        guard
            !Task.isCancelled,
            accountScope.check(),
            pipelineGeneration == generation
        else {
            return
        }
        pipelineState =
            .loaded(event.value)
        pipelineRefreshError = nil
        pipelineSource = event.source
        pipelineCacheStoredAt =
            event.cacheStoredAt
    }

    private func restorePipelineState(
        state:
            GitLabResourceDetailState<
                GitLabPipeline
            >,
        refreshError:
            GitLabSessionClientError?,
        source: GitLabAPIResponseSource?,
        cacheStoredAt: Date?,
        generation: UInt64
    ) {
        guard
            pipelineGeneration == generation
        else {
            return
        }
        pipelineState = state
        pipelineRefreshError =
            refreshError
        pipelineSource = source
        pipelineCacheStoredAt =
            cacheStoredAt
    }

    private func observeStageRevisions() async {
        for await revisions in Observations({
            (
                self.jobs.contentRevision,
                self.triggerJobs.contentRevision
            )
        }) {
            guard
                !Task.isCancelled,
                accountScope.check()
            else {
                return
            }
            _ = revisions
            await projectStages()
        }
    }

    private func projectStages() async {
        guard accountScope.check() else {
            return
        }
        projectionGeneration &+= 1
        let generation =
            projectionGeneration
        let jobs = jobs.items
        let triggerJobs =
            triggerJobs.items
        isProjectingStages = true

        let projected =
            await GitLabPipelineStageProjector
            .project(
                jobs: jobs,
                triggerJobs: triggerJobs
            )

        guard
            !Task.isCancelled,
            accountScope.check(),
            projectionGeneration
                == generation
        else {
            if
                projectionGeneration
                    == generation
            {
                isProjectingStages = false
            }
            return
        }
        stages = projected
        isProjectingStages = false
    }

    private static func makeJobsModel(
        route: GitLabPipelineRoute,
        cacheLifetime:
            GitLabPipelineCacheLifetime,
        loader: any GitLabPipelineLoading,
        accountScope:
            GitLabPipelineAccountScope
    ) -> GitLabPaginatedResourceModel<
        GitLabPipelineJob,
        Int
    > {
        GitLabPaginatedResourceModel(
            loadPage: {
                nextPageURL async throws(
                    GitLabSessionClientError
                ) in
                guard
                    await accountScope.check()
                else {
                    throw .api(.cancelled)
                }
                let page =
                    try await loader
                    .loadPipelineJobsPage(
                        at: route,
                        after: nextPageURL
                    )
                guard
                    await accountScope.check()
                else {
                    throw .api(.cancelled)
                }
                return page
            },
            loadFirstPage: {
                refreshBehavior,
                onPage async throws(
                    GitLabSessionClientError
                ) in
                guard
                    await accountScope.check()
                else {
                    throw .api(.cancelled)
                }
                try await loader
                    .loadPipelineJobsFirstPage(
                        at: route,
                        cacheLifetime:
                            cacheLifetime,
                        refreshBehavior:
                            refreshBehavior
                    ) { event in
                        guard
                            await accountScope
                                .check()
                        else {
                            return
                        }
                        await onPage(event)
                    }
                guard
                    await accountScope.check()
                else {
                    throw .api(.cancelled)
                }
            },
            firstPageRefreshMode:
                .retainLoadedTail,
            identity: \.id,
            searchValues: {
                [
                    $0.name,
                    $0.stage,
                    $0.status.title,
                    $0.ref ?? "",
                    String($0.id),
                ]
            }
        )
    }

    private static func makeTriggerJobsModel(
        route: GitLabPipelineRoute,
        cacheLifetime:
            GitLabPipelineCacheLifetime,
        loader: any GitLabPipelineLoading,
        accountScope:
            GitLabPipelineAccountScope,
        capabilityStore:
            GitLabPipelineTriggerCapabilityStore
    ) -> GitLabPaginatedResourceModel<
        GitLabPipelineTriggerJob,
        Int
    > {
        GitLabPaginatedResourceModel(
            loadPage: {
                nextPageURL async throws(
                    GitLabSessionClientError
                ) in
                guard
                    await accountScope.check()
                else {
                    throw .api(.cancelled)
                }
                let capability =
                    await capabilityStore
                    .current()
                let result =
                    try await loader
                    .loadPipelineTriggerJobsPage(
                        at: route,
                        capability: capability,
                        after: nextPageURL
                    )
                guard
                    await accountScope.check()
                else {
                    throw .api(.cancelled)
                }
                await capabilityStore.select(
                    result.capability
                )
                return result.page
            },
            loadFirstPage: {
                refreshBehavior,
                onPage async throws(
                    GitLabSessionClientError
                ) in
                guard
                    await accountScope.check()
                else {
                    throw .api(.cancelled)
                }
                let capability =
                    await capabilityStore
                    .current()
                let selected =
                    try await loader
                    .loadPipelineTriggerJobsFirstPage(
                        at: route,
                        capability: capability,
                        cacheLifetime:
                            cacheLifetime,
                        refreshBehavior:
                            refreshBehavior
                    ) { event in
                        guard
                            await accountScope
                                .check()
                        else {
                            return
                        }
                        await onPage(event)
                    }
                guard
                    await accountScope.check()
                else {
                    throw .api(.cancelled)
                }
                await capabilityStore.select(
                    selected
                )
            },
            firstPageRefreshMode:
                .retainLoadedTail,
            identity: \.id,
            searchValues: {
                [
                    $0.name,
                    $0.stage,
                    $0.status.title,
                    String($0.id),
                    $0.downstreamPipeline?
                        .ref ?? "",
                ]
            }
        )
    }

    private static func job(
        _ job: GitLabPipelineJob,
        belongsTo route:
            GitLabPipelineRoute
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
