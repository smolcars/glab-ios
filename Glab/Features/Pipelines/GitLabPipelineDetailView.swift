import SwiftUI

struct GitLabPipelineDetailView: View {
    let loader: any GitLabPipelineLoading
    let accountID: GitLabAccountID
    let appSession: AppSession
    let apiAccess: GitLabAPIAccess
    let isAccountCurrent:
        @MainActor () -> Bool

    @State private var model:
        GitLabPipelineDetailModel
    @State private var actionModel:
        GitLabPipelineActionModel?
    @State private var expandedStageIDs:
        Set<String> = []
    @State private var
        didInitializeStageExpansion = false
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.gitLabJobTraceLoader)
    private var jobTraceLoader
    @Environment(\.gitLabPipelineActionService)
    private var actionService

    init(
        route: GitLabPipelineRoute,
        cacheLifetime:
            GitLabPipelineCacheLifetime,
        loader: any GitLabPipelineLoading,
        accountID: GitLabAccountID,
        appSession: AppSession,
        apiAccess: GitLabAPIAccess
    ) {
        self.init(
            route: route,
            cacheLifetime: cacheLifetime,
            loader: loader,
            accountID: accountID,
            appSession: appSession,
            apiAccess: apiAccess,
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
        apiAccess: GitLabAPIAccess,
        isAccountCurrent:
            @escaping @MainActor () -> Bool
    ) {
        self.loader = loader
        self.accountID = accountID
        self.appSession = appSession
        self.apiAccess = apiAccess
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
        GlabList {
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
            ToolbarItemGroup(
                placement: .topBarTrailing
            ) {
                pipelineActionControl

                if
                    let destination =
                        model.pipeline?
                        .safeWebURL
                {
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
            prepareActionModelIfNeeded()
            await model.runVisible(
                isSceneActive:
                    scenePhase == .active
            )
            await handleAuthenticationFailure()
        }
        .alert(
            actionModel?.confirmation?.title
                ?? "Confirm pipeline action",
            isPresented:
                actionConfirmationIsPresented,
            presenting:
                actionModel?.confirmation
        ) { confirmation in
            Button(
                confirmation.action.title,
                role:
                    confirmation.action
                    .consumesRunnerResources
                    == true
                    ? nil
                    : .destructive
            ) {
                Task {
                    await actionModel?
                        .confirm(
                            confirmation
                        )
                    await handleAuthenticationFailure()
                }
            }
            Button("Cancel", role: .cancel) {
                actionModel?
                    .dismissConfirmation()
            }
        } message: { confirmation in
            Text(
                confirmation.message
            )
        }
        .alert(
            "Couldn’t update pipeline",
            isPresented:
                actionFailureIsPresented
        ) {
            Button("OK") {
                actionModel?.dismissFailure()
            }
        } message: {
            Text(
                actionModel?
                    .failure?
                    .localizedDescription
                    ?? ""
            )
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
    private var pipelineActionControl:
        some View
    {
        if actionModel?.isBusy == true {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(
                    "Updating pipeline"
                )
                .accessibilityIdentifier(
                    "pipelines.detail.action.progress"
                )
        } else if
            let action =
                actionModel?
                .availablePipelineActions
                .first
        {
            Button {
                actionModel?.request(action)
            } label: {
                Image(
                    systemName:
                        action.systemImage
                )
            }
            .accessibilityLabel(action.title)
            .accessibilityHint(
                "Shows a confirmation before changing this pipeline."
            )
            .accessibilityIdentifier(
                "pipelines.detail.action.\(action.rawValue)"
            )
        }
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
                            .glabHeadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(.primary)

                    Text(
                        "\(stage.rows.count)"
                    )
                    .font(
                        .subheadline
                            .monospacedDigit()
                    )
                    .foregroundStyle(.secondary)

                    Spacer()

                    if stage.hasAnimatingRows {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityHidden(true)
                    } else if stage
                        .hasWaitingRows
                    {
                        Image(
                            systemName: "hourglass"
                        )
                        .font(
                            .glabCaption.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            Color.glabAccent
                        )
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    }

                    Image(
                        systemName:
                            expandedStageIDs
                            .contains(stage.id)
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(.glabBody.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(
                        width: 32,
                        height: 32
                    )
                    .background(
                        .fill.tertiary,
                        in: .circle
                    )
                    .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .textCase(nil)
            .accessibilityLabel(
                "\(stage.name), \(stage.rows.count) jobs"
            )
            .accessibilityValue(
                stageAccessibilityValue(
                    stage
                )
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

    private func stageAccessibilityValue(
        _ stage: GitLabPipelineStage
    ) -> String {
        var values = [
            expandedStageIDs
                .contains(stage.id)
                ? "Expanded"
                : "Collapsed"
        ]
        if stage.hasAnimatingRows {
            values.append("In progress")
        } else if stage.hasWaitingRows {
            values.append("Waiting")
        }
        return values.joined(separator: ", ")
    }

    @ViewBuilder
    private func pipelineRow(
        _ row: GitLabPipelineStageRow
    ) -> some View {
        switch row.content {
        case let .job(job):
            if
                let context =
                    row.jobTraceContext(
                        projectID:
                            model.route
                            .projectID
                    )
            {
                HStack(spacing: 8) {
                    NavigationLink {
                        GitLabJobTraceView(
                            accountID:
                                accountID,
                            context: context,
                            loader:
                                jobTraceLoader,
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

                    jobActionControl(
                        job
                    )
                }
            } else {
                HStack(spacing: 8) {
                    GitLabPipelineJobRow(
                        row: row
                    )

                    jobActionControl(
                        job
                    )
                }
            }
        case let .triggerJob(triggerJob):
            if
                let downstreamRoute =
                    triggerJob
                    .downstreamRoute,
                let downstreamPipeline =
                    triggerJob
                    .downstreamPipeline
            {
                HStack(spacing: 8) {
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
                                apiAccess:
                                    apiAccess,
                                isAccountCurrent:
                                isAccountCurrent
                        )
                    } label: {
                        GitLabPipelineJobRow(
                            row: row
                        )
                    }

                    triggerJobActionControl(
                        triggerJob
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

                    triggerJobActionControl(
                        triggerJob
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func jobActionControl(
        _ job: GitLabPipelineJob
    ) -> some View {
        if
            let action =
                actionModel?
                .availableJobActions(
                    for: job
                )
                .first
        {
            pipelineActionButton(
                action: action,
                resourceName: job.name,
                accessibilityIdentifier:
                    "pipelines.detail.job.\(job.id).action.\(action.rawValue)"
            ) {
                actionModel?.request(
                    action,
                    job: job
                )
            }
        }
    }

    @ViewBuilder
    private func triggerJobActionControl(
        _ triggerJob:
            GitLabPipelineTriggerJob
    ) -> some View {
        if
            let action =
                actionModel?
                .availableTriggerJobActions(
                    for: triggerJob
                )
                .first
        {
            pipelineActionButton(
                action: action,
                resourceName:
                    triggerJob.name,
                accessibilityIdentifier:
                    "pipelines.detail.triggerJob.\(triggerJob.id).action.\(action.rawValue)"
            ) {
                actionModel?.request(
                    action,
                    triggerJob: triggerJob
                )
            }
        }
    }

    private func pipelineActionButton(
        action: GitLabPipelineActionKind,
        resourceName: String,
        accessibilityIdentifier: String,
        request: @escaping () -> Void
    ) -> some View {
        Button(action: request) {
            Image(
                systemName:
                    action.systemImage
            )
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .frame(
            minWidth: 44,
            minHeight: 44
        )
        .disabled(
            actionModel?.isBusy == true
        )
        .accessibilityLabel(
            "\(action.title), \(resourceName)"
        )
        .accessibilityHint(
            "Shows a confirmation before changing this pipeline job."
        )
        .accessibilityIdentifier(
            accessibilityIdentifier
        )
    }

    private var actionConfirmationIsPresented:
        Binding<Bool>
    {
        Binding {
            actionModel?.confirmation != nil
        } set: { isPresented in
            if !isPresented {
                actionModel?
                    .dismissConfirmation()
            }
        }
    }

    private var actionFailureIsPresented:
        Binding<Bool>
    {
        Binding {
            actionModel?.failure != nil
        } set: { isPresented in
            if !isPresented {
                actionModel?.dismissFailure()
            }
        }
    }

    private func prepareActionModelIfNeeded() {
        guard actionModel == nil else {
            return
        }
        let detailModel = model
        actionModel =
            GitLabPipelineActionModel(
                accountID: accountID,
                route: detailModel.route,
                apiAccess: apiAccess,
                service: actionService,
                traceStore:
                    appSession
                    .jobTraceStore,
                isAccountCurrent:
                    isAccountCurrent,
                currentPipeline: {
                    detailModel.pipeline
                },
                currentJobs: {
                    detailModel.jobs.items
                },
                currentTriggerJobs: {
                    detailModel
                        .triggerJobs.items
                },
                reconcilePipeline: {
                    detailModel
                        .reconcileActionPipeline(
                            $0
                        )
                },
                reconcileJob: {
                    await detailModel
                        .reconcileActionJob($0)
                },
                reconcileTriggerJob: {
                    await detailModel
                        .reconcileActionTriggerJob(
                            $0
                        )
                },
                refresh: {
                    await detailModel
                        .refresh()
                }
            )
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
                .font(.glabFootnote)
            Spacer()
        }
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error =
                actionModel?
                .authenticationFailure
                ?? model
                .authenticationFailure
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
