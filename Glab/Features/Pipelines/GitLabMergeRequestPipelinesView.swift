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
                if
                    let pipelineRoute =
                        GitLabPipelineRoute(
                            projectID:
                                model.route
                                .projectID,
                            pipelineID:
                                pipeline.id
                        )
                {
                    NavigationLink {
                        GitLabPipelineDetailView(
                            route:
                                pipelineRoute,
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
