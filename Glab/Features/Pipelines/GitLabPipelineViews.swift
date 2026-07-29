import SwiftUI

struct GitLabMergeRequestPipelinesView: View {
    let loader: any GitLabPipelineLoading
    let accountID: GitLabAccountID
    let appSession: AppSession
    let isAccountCurrent:
        @MainActor () -> Bool

    @State private var model:
        GitLabMergeRequestPipelinesModel
    @Environment(\.scenePhase)
    private var scenePhase

    init(
        route: GitLabMergeRequestRoute,
        loader: any GitLabPipelineLoading,
        accountID: GitLabAccountID,
        appSession: AppSession
    ) {
        self.init(
            route: route,
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
        route: GitLabMergeRequestRoute,
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
                GitLabMergeRequestPipelinesModel(
                    accountID: accountID,
                    route: route,
                    loader: loader,
                    isAccountCurrent:
                        isAccountCurrent
                )
        )
    }

    var body: some View {
        List {
            pipelineRows
        }
        .listStyle(.plain)
        .navigationTitle("Pipelines")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(
            "pipelines.history.list"
        )
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
    }

    @ViewBuilder
    private var pipelineRows: some View {
        if
            model.pipelines.didFailRefresh,
            let error =
                model.pipelines.loadError
        {
            GitLabInlineRetryRow(
                title:
                    "Couldn’t refresh pipelines",
                error: error,
                accessibilityIdentifier:
                    "pipelines.history.refreshError"
            ) {
                Task {
                    await model.refresh()
                    await handleAuthenticationFailure()
                }
            }
        }

        if
            model.pipelines.items.isEmpty,
            model.pipelines.isLoadingInitial
        {
            loadingRow("Loading pipelines…")
        } else if
            model.pipelines.items.isEmpty,
            let error =
                model.pipelines.loadError
        {
            GitLabInlineRetryRow(
                title:
                    "Couldn’t load pipelines",
                error: error,
                accessibilityIdentifier:
                    "pipelines.history.loadError"
            ) {
                Task {
                    await model.refresh()
                    await handleAuthenticationFailure()
                }
            }
        } else if
            model.pipelines.items.isEmpty,
            model.pipelines.hasLoaded
        {
            ContentUnavailableView(
                "No pipelines",
                systemImage:
                    "point.3.connected.trianglepath.dotted",
                description:
                    Text(
                        "This merge request has no pipelines."
                    )
            )
            .listRowBackground(Color.clear)
            .accessibilityIdentifier(
                "pipelines.history.empty"
            )
        } else {
            ForEach(
                model.pipelines.items
            ) { pipeline in
                NavigationLink {
                    GitLabPipelineDetailView(
                        route:
                            GitLabPipelineRoute(
                                projectID:
                                    model.route
                                    .projectID,
                                pipelineID:
                                    pipeline.id
                            )!,
                        cacheLifetime:
                            pipeline
                            .detailCacheLifetime,
                        loader: loader,
                        accountID: accountID,
                        appSession:
                            appSession,
                        isAccountCurrent:
                            isAccountCurrent
                    )
                } label: {
                    GitLabPipelineHistoryRow(
                        pipeline: pipeline
                    )
                }
                .accessibilityIdentifier(
                    "pipelines.history.row.\(pipeline.id)"
                )
                .task {
                    await model
                        .loadNextPageIfNeeded(
                            after: pipeline
                        )
                    await handleAuthenticationFailure()
                }
            }
        }

        if model.pipelines.isLoadingNextPage {
            loadingRow("Loading more…")
        } else if
            model.pipelines.didFailNextPage,
            let error =
                model.pipelines.loadError
        {
            GitLabInlineRetryRow(
                title:
                    "Couldn’t load more pipelines",
                error: error,
                accessibilityIdentifier:
                    "pipelines.history.nextPageError"
            ) {
                Task {
                    await model.retryNextPage()
                    await handleAuthenticationFailure()
                }
            }
        }
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
        .listRowBackground(Color.clear)
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

private struct GitLabPipelineHistoryRow:
    View
{
    let pipeline: GitLabPipeline

    var body: some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            GitLabCIStatusIcon(
                status: pipeline.status
            )
            .padding(.top, 2)

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(
                    pipeline.name
                    ?? "Pipeline \(pipeline.displayID)"
                )
                .font(
                    .body.weight(.semibold)
                )
                .lineLimit(3)

                (
                    Text(pipeline.status.title)
                        .foregroundStyle(
                            pipeline.status.tint
                        )
                    + Text("  \(pipeline.ref)  ")
                    + Text(pipeline.shortSHA)
                        .fontDesign(.monospaced)
                    + Text(
                        pipeline.relativeTime
                            .map { "  \($0)" }
                            ?? ""
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            [
                pipeline.name
                    ?? "Pipeline \(pipeline.displayID)",
                pipeline.status.title,
                pipeline.ref,
                pipeline.shortSHA,
            ]
            .joined(separator: ", ")
        )
    }
}

private struct GitLabPipelineHeader: View {
    let pipeline: GitLabPipeline

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            if let name = pipeline.name {
                Text(name)
                    .font(
                        .headline
                    )
            }

            HStack(spacing: 8) {
                GitLabCIStatusIcon(
                    status: pipeline.status
                )

                Text(pipeline.status.title)
                    .font(
                        .body.weight(.semibold)
                    )
                    .foregroundStyle(
                        pipeline.status.tint
                    )

                Text(pipeline.displayID)
                    .font(
                        .caption
                            .monospacedDigit()
                    )
                    .foregroundStyle(.secondary)
            }

            HStack(
                alignment: .firstTextBaseline,
                spacing: 6
            ) {
                Image(
                    systemName:
                        "arrow.triangle.branch"
                )
                .accessibilityHidden(true)

                (
                    Text(pipeline.ref)
                    + Text("  ")
                    + Text(pipeline.shortSHA)
                        .fontDesign(.monospaced)
                )
                .lineLimit(3)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if !pipeline.metadataSummary.isEmpty {
                Text(
                    pipeline.metadataSummary
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(
            children: .combine
        )
        .accessibilityIdentifier(
            "pipelines.detail.header"
        )
    }
}

private struct GitLabPipelineJobRow: View {
    let row: GitLabPipelineStageRow

    var body: some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            GitLabCIStatusIcon(
                status: row.status
            )
            .padding(.top, 2)

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(row.name)
                    .font(
                        .body.weight(.medium)
                    )
                    .lineLimit(3)

                Text(row.metadataSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

                if
                    let downstreamSummary =
                        row.downstreamSummary
                {
                    Text(downstreamSummary)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            row.accessibilityLabel
        )
        .accessibilityIdentifier(
            row.accessibilityIdentifier
        )
    }

}

private struct GitLabCIStatusIcon: View {
    let status: GitLabCIStatus

    var body: some View {
        Image(
            systemName:
                status.systemImage
        )
        .font(.body)
        .foregroundStyle(status.tint)
        .frame(width: 22)
        .accessibilityHidden(true)
    }
}

private extension GitLabPipeline {
    var displayID: String {
        "#\(iid ?? id)"
    }

    var shortSHA: String {
        String(sha.prefix(8))
    }

    var detailCacheLifetime:
        GitLabPipelineCacheLifetime
    {
        status.isTerminal
            ? .completed
            : .active
    }

    var metadataSummary: String {
        var values: [String] = []
        if let source {
            values.append(
                source.replacingOccurrences(
                    of: "_",
                    with: " "
                )
            )
        }
        if let user {
            values.append(user.displayName)
        }
        if
            let duration,
            let formatted =
                GitLabDurationFormatter
                .string(seconds: duration)
        {
            values.append(formatted)
        }
        if
            let date =
                finishedAt
                ?? updatedAt
                ?? startedAt
                ?? createdAt
        {
            values.append(
                GitLabRelativeTimeFormatter
                    .string(from: date)
            )
        }
        return values.joined(
            separator: " · "
        )
    }

    var relativeTime: String? {
        guard
            let date = updatedAt ?? createdAt
        else {
            return nil
        }
        return GitLabRelativeTimeFormatter
            .string(from: date)
    }
}

private extension GitLabPipelineStageRow {
    var allowsFailure: Bool {
        switch content {
        case let .job(job):
            job.allowFailure
        case let .triggerJob(job):
            job.allowFailure
        }
    }

    var durationText: String? {
        let duration:
            TimeInterval? =
            switch content {
            case let .job(job):
                job.duration
            case let .triggerJob(job):
                job.duration
            }
        guard let duration else {
            return nil
        }
        return GitLabDurationFormatter
            .string(seconds: duration)
    }

    var downstreamSummary: String? {
        guard
            case let .triggerJob(job) =
                content,
            let pipeline =
                job.downstreamPipeline
        else {
            return nil
        }
        return [
            pipeline.status.title,
            pipeline.ref,
            pipeline.shortSHA,
        ]
        .joined(separator: " · ")
    }

    var metadataSummary: String {
        var values: [String] = []
        if case .triggerJob = content {
            values.append("Child")
        }
        values.append(status.title)
        if attempt != .only {
            values.append(attempt.title)
        }
        if let durationText {
            values.append(durationText)
        }
        if allowsFailure {
            values.append("Allowed")
        }
        return values.joined(
            separator: " · "
        )
    }

    var accessibilityLabel: String {
        var values = [
            name,
            status.title,
        ]
        if case .triggerJob = content {
            values.append("Child pipeline")
        }
        if attempt != .only {
            values.append(attempt.title)
        }
        if allowsFailure {
            values.append("Failure allowed")
        }
        if let durationText {
            values.append(durationText)
        }
        if let downstreamSummary {
            values.append(downstreamSummary)
        }
        return values.joined(
            separator: ", "
        )
    }

    var accessibilityIdentifier: String {
        switch id {
        case let .job(id):
            "pipelines.detail.job.\(id)"
        case let .triggerJob(id):
            "pipelines.detail.triggerJob.\(id)"
        }
    }
}

private extension GitLabPipelineJobAttempt {
    var title: String {
        switch self {
        case .only:
            ""
        case .latest:
            "Latest run"
        case .earlier:
            "Earlier run"
        }
    }
}

extension GitLabCIStatus {
    var systemImage: String {
        switch rawValue {
        case "created":
            "circle.dotted"
        case "waiting_for_resource",
             "waiting_for_callback":
            "hourglass"
        case "preparing":
            "wrench.and.screwdriver.fill"
        case "pending":
            "clock.fill"
        case "running":
            "play.circle.fill"
        case "canceling":
            "xmark.circle"
        case "scheduled":
            "calendar.badge.clock"
        case "manual":
            "hand.tap.fill"
        case "success":
            "checkmark.circle.fill"
        case "failed":
            "xmark.circle.fill"
        case "canceled":
            "slash.circle.fill"
        case "skipped":
            "forward.end.circle.fill"
        default:
            "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch rawValue {
        case "success":
            .green
        case "failed":
            .red
        case "canceled",
             "skipped":
            .secondary
        case "manual":
            .orange
        case "created",
             "waiting_for_resource",
             "preparing",
             "waiting_for_callback",
             "pending",
             "running",
             "canceling",
             "scheduled":
            .blue
        default:
            .secondary
        }
    }
}
