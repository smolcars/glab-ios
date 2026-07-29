import SwiftUI

struct GitLabPipelineDetailView: View {
    let loader: any GitLabPipelineLoading
    let accountID: GitLabAccountID
    let appSession: AppSession
    let isAccountCurrent:
        @MainActor () -> Bool

    @State private var model:
        GitLabPipelineDetailModel
    @State private var expandedStageIDs:
        Set<String> = []
    @State private var
        didInitializeStageExpansion = false
    @Environment(\.scenePhase)
    private var scenePhase

    init(
        route: GitLabPipelineRoute,
        cacheLifetime:
            GitLabPipelineCacheLifetime,
        loader: any GitLabPipelineLoading,
        accountID: GitLabAccountID,
        appSession: AppSession
    ) {
        self.init(
            route: route,
            cacheLifetime: cacheLifetime,
            loader: loader,
            accountID: accountID,
            appSession: appSession,
            isAccountCurrent: {
                appSession.activeAccountID
                    == accountID
            }
        )
    }

    init(
        route: GitLabPipelineRoute,
        cacheLifetime:
            GitLabPipelineCacheLifetime,
        loader: any GitLabPipelineLoading,
        accountID: GitLabAccountID,
        appSession: AppSession,
        isAccountCurrent:
            @escaping @MainActor () -> Bool
    ) {
        self.loader = loader
        self.accountID = accountID
        self.appSession = appSession
        self.isAccountCurrent =
            isAccountCurrent
        _model = State(
            initialValue:
                GitLabPipelineDetailModel(
                    accountID: accountID,
                    route: route,
                    cacheLifetime:
                        cacheLifetime,
                    loader: loader,
                    isAccountCurrent:
                        isAccountCurrent
                )
        )
    }

    var body: some View {
        List {
            pipelineSection
            failureRows
            stageRows
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle(
            "Pipeline #\(model.pipeline?.iid ?? model.route.pipelineID)"
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if
                let destination =
                    model.pipeline?
                    .safeWebURL
            {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Link(
                        destination:
                            destination
                    ) {
                        GitLabLogoMark()
                    }
                    .accessibilityLabel(
                        "Open pipeline in GitLab"
                    )
                    .accessibilityIdentifier(
                        "pipelines.detail.openInGitLab"
                    )
                }
            }
        }
        .refreshable {
            await model.refresh()
            await handleAuthenticationFailure()
        }
        .task(id: scenePhase) {
            await model.runVisible(
                isSceneActive:
                    scenePhase == .active
            )
            await handleAuthenticationFailure()
        }
        .onChange(
            of: model.stages.map(\.id),
            initial: true
        ) { _, stageIDs in
            expandedStageIDs
                .formIntersection(stageIDs)
            guard
                !didInitializeStageExpansion,
                let first = stageIDs.first
            else {
                return
            }
            expandedStageIDs.insert(first)
            didInitializeStageExpansion = true
        }
        .onChange(
            of: model.authenticationFailure
        ) { _, error in
            guard let error else {
                return
            }
            Task {
                await appSession
                    .handleAuthenticationFailure(
                        error,
                        for: accountID
                    )
            }
        }
        .accessibilityIdentifier(
            "pipelines.detail.list"
        )
    }

    @ViewBuilder
    private var pipelineSection: some View {
        switch model.pipelineState {
        case .idle, .loading:
            Section {
                loadingRow(
                    "Loading pipeline…"
                )
            }
        case let .failed(error):
            Section {
                GitLabInlineRetryRow(
                    title:
                        "Couldn’t load pipeline details",
                    error: error,
                    accessibilityIdentifier:
                        "pipelines.detail.loadError"
                ) {
                    Task {
                        await model.refresh()
                        await handleAuthenticationFailure()
                    }
                }
            }
        case let .loaded(pipeline):
            Section {
                GitLabPipelineHeader(
                    pipeline: pipeline
                )
            }
        }
    }

    @ViewBuilder
    private var failureRows: some View {
        if let error =
            model.pipelineRefreshError
        {
            Section {
                GitLabInlineRetryRow(
                    title:
                        "Couldn’t refresh pipeline details",
                    error: error,
                    accessibilityIdentifier:
                        "pipelines.detail.refreshError"
                ) {
                    Task {
                        await model.refresh()
                        await handleAuthenticationFailure()
                    }
                }
            }
        }

        if
            !model.jobs.didFailNextPage,
            let error = model.jobs.loadError
        {
            Section {
                GitLabInlineRetryRow(
                    title:
                        model.jobs.items.isEmpty
                        ? "Couldn’t load jobs"
                        : "Couldn’t refresh jobs",
                    error: error,
                    accessibilityIdentifier:
                        "pipelines.detail.jobsError"
                ) {
                    Task {
                        await model.refresh()
                        await handleAuthenticationFailure()
                    }
                }
            }
        }

        if
            !model.triggerJobs
                .didFailNextPage,
            let error =
                model.triggerJobs.loadError
        {
            Section {
                GitLabInlineRetryRow(
                    title:
                        model.triggerJobs.items
                        .isEmpty
                        ? "Child pipelines unavailable"
                        : "Couldn’t refresh child pipelines",
                    error: error,
                    accessibilityIdentifier:
                        "pipelines.detail.triggerJobsError"
                ) {
                    Task {
                        await model.refresh()
                        await handleAuthenticationFailure()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stageRows: some View {
        if
            model.stages.isEmpty,
            (
                model.jobs.isLoadingInitial
                    || model.triggerJobs
                    .isLoadingInitial
                    || model
                    .isProjectingStages
            )
        {
            Section {
                loadingRow("Loading jobs…")
            }
        } else if
            model.stages.isEmpty,
            model.jobs.hasLoaded,
            model.triggerJobs.hasLoaded,
            model.jobs.loadError == nil,
            model.triggerJobs.loadError
                == nil
        {
            Section {
                ContentUnavailableView(
                    "No jobs",
                    systemImage:
                        "square.stack.3d.up.slash",
                    description:
                        Text(
                            "This pipeline has no jobs."
                        )
                )
                .accessibilityIdentifier(
                    "pipelines.detail.empty"
                )
            }
        } else {
            ForEach(model.stages) {
                stage in
                stageSection(stage)
            }
        }

        if
            model.jobs.isLoadingNextPage
                || model.triggerJobs
                .isLoadingNextPage
        {
            Section {
                loadingRow("Loading more jobs…")
            }
        }

        if
            model.jobs.didFailNextPage,
            let error = model.jobs.loadError
        {
            Section {
                GitLabInlineRetryRow(
                    title:
                        "Couldn’t load more jobs",
                    error: error,
                    accessibilityIdentifier:
                        "pipelines.detail.jobsNextPageError"
                ) {
                    Task {
                        await model
                            .retryJobsNextPage()
                        await handleAuthenticationFailure()
                    }
                }
            }
        }

        if
            model.triggerJobs
                .didFailNextPage,
            let error =
                model.triggerJobs.loadError
        {
            Section {
                GitLabInlineRetryRow(
                    title:
                        "Couldn’t load more child pipelines",
                    error: error,
                    accessibilityIdentifier:
                        "pipelines.detail.triggerJobsNextPageError"
                ) {
                    Task {
                        await model
                            .retryTriggerJobsNextPage()
                        await handleAuthenticationFailure()
                    }
                }
            }
        }
    }

    private func stageSection(
        _ stage: GitLabPipelineStage
    ) -> some View {
        Section {
            if expandedStageIDs.contains(
                stage.id
            ) {
                ForEach(stage.rows) { row in
                    pipelineRow(row)
                        .task {
                            await paginate(
                                after: row
                            )
                        }
                }
            }
        } header: {
            Button {
                if expandedStageIDs
                    .contains(stage.id)
                {
                    expandedStageIDs.remove(
                        stage.id
                    )
                } else {
                    expandedStageIDs.insert(
                        stage.id
                    )
                }
            } label: {
                HStack(spacing: 8) {
                    Text(stage.name)
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(.primary)

                    Text(
                        "\(stage.rows.count)"
                    )
                    .font(
                        .caption
                            .monospacedDigit()
                    )
                    .foregroundStyle(.secondary)

                    Spacer()

                    if stage
                        .hasActivelyChangingRows
                    {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityHidden(true)
                    }

                    Image(
                        systemName:
                            expandedStageIDs
                            .contains(stage.id)
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                }
                .frame(minHeight: 36)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .textCase(nil)
            .accessibilityLabel(
                "\(stage.name), \(stage.rows.count) jobs"
            )
            .accessibilityValue(
                expandedStageIDs
                    .contains(stage.id)
                ? "Expanded"
                : "Collapsed"
            )
            .accessibilityHint(
                expandedStageIDs
                    .contains(stage.id)
                ? "Collapses this stage."
                : "Expands this stage."
            )
            .accessibilityIdentifier(
                "pipelines.detail.stage.\(stage.id)"
            )
        }
    }

    @ViewBuilder
    private func pipelineRow(
        _ row: GitLabPipelineStageRow
    ) -> some View {
        switch row.content {
        case .job:
            GitLabPipelineJobRow(row: row)
        case let .triggerJob(triggerJob):
            if
                let downstreamRoute =
                    triggerJob
                    .downstreamRoute,
                let downstreamPipeline =
                    triggerJob
                    .downstreamPipeline
            {
                NavigationLink {
                    GitLabPipelineDetailView(
                        route:
                            downstreamRoute,
                        cacheLifetime:
                            downstreamPipeline
                            .detailCacheLifetime,
                        loader: loader,
                        accountID:
                            accountID,
                        appSession:
                            appSession,
                        isAccountCurrent:
                            isAccountCurrent
                    )
                } label: {
                    GitLabPipelineJobRow(
                        row: row
                    )
                }
            } else {
                HStack(spacing: 8) {
                    GitLabPipelineJobRow(
                        row: row
                    )

                    if
                        let destination =
                            triggerJob
                            .downstreamPipeline?
                            .safeWebURL
                    {
                        Link(
                            destination:
                                destination
                        ) {
                            GitLabLogoMark()
                        }
                        .accessibilityLabel(
                            "Open child pipeline in GitLab"
                        )
                    }
                }
            }
        }
    }

    private func paginate(
        after row:
            GitLabPipelineStageRow
    ) async {
        switch row.content {
        case let .job(job):
            await model
                .loadNextJobsPageIfNeeded(
                    after: job
                )
        case let .triggerJob(job):
            await model
                .loadNextTriggerJobsPageIfNeeded(
                    after: job
                )
        }
        await handleAuthenticationFailure()
    }

    private func loadingRow(
        _ title: String
    ) -> some View {
        HStack {
            Spacer()
            ProgressView(title)
                .font(.footnote)
            Spacer()
        }
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error =
                model.authenticationFailure
        else {
            return
        }
        await appSession
            .handleAuthenticationFailure(
                error,
                for: accountID
            )
    }
}
