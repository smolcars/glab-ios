import SwiftUI

struct GitLabMergeRequestPipelinesView: View {
    let loader: any GitLabPipelineLoading
    let accountID: GitLabAccountID
    let appSession: AppSession
    let apiAccess: GitLabAPIAccess
    let isAccountCurrent:
        @MainActor () -> Bool
    let isMergeRequestOpen:
        @MainActor () -> Bool

    @State private var model:
        GitLabMergeRequestPipelinesModel
    @State private var creationModel:
        GitLabMergeRequestPipelineCreationModel?
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.gitLabPipelineActionService)
    private var actionService

    init(
        route: GitLabMergeRequestRoute,
        loader: any GitLabPipelineLoading,
        accountID: GitLabAccountID,
        appSession: AppSession,
        apiAccess: GitLabAPIAccess,
        isAccountCurrent:
            @escaping @MainActor () -> Bool,
        isMergeRequestOpen:
            @escaping @MainActor () -> Bool
    ) {
        self.loader = loader
        self.accountID = accountID
        self.appSession = appSession
        self.apiAccess = apiAccess
        self.isAccountCurrent =
            isAccountCurrent
        self.isMergeRequestOpen =
            isMergeRequestOpen
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
        GlabList {
            pipelineRows
        }
        .listStyle(.plain)
        .navigationTitle("Pipelines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if creationModel?.isCreating == true {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(
                            "Creating pipeline"
                        )
                        .accessibilityIdentifier(
                            "pipelines.history.create.progress"
                        )
                }
            } else if
                creationModel?.canCreate
                    == true
            {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button {
                        creationModel?.request()
                    } label: {
                        Image(
                            systemName:
                                "plus"
                        )
                    }
                    .accessibilityLabel(
                        "Create merge request pipeline"
                    )
                    .accessibilityHint(
                        "Shows a confirmation before creating a pipeline."
                    )
                    .accessibilityIdentifier(
                        "pipelines.history.create"
                    )
                }
            }
        }
        .accessibilityIdentifier(
            "pipelines.history.list"
        )
        .refreshable {
            await model.refresh()
            await handleAuthenticationFailure()
        }
        .task(id: scenePhase) {
            prepareCreationModelIfNeeded()
            await model.runVisible(
                isSceneActive:
                    scenePhase == .active
            )
            await handleAuthenticationFailure()
        }
        .alert(
            "Create pipeline?",
            isPresented:
                creationConfirmationIsPresented
        ) {
            Button("Create") {
                Task {
                    await creationModel?
                        .confirm()
                    await handleAuthenticationFailure()
                }
            }
            Button("Cancel", role: .cancel) {
                creationModel?
                    .dismissConfirmation()
            }
        } message: {
            Text(
                "Create a new pipeline for this merge request. This can consume CI runner resources."
            )
        }
        .alert(
            "Couldn’t create pipeline",
            isPresented:
                creationFailureIsPresented
        ) {
            Button("OK") {
                creationModel?
                    .dismissFailure()
            }
        } message: {
            Text(
                creationModel?
                    .failure?
                    .localizedDescription
                    ?? ""
            )
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
                            apiAccess:
                                apiAccess,
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

    private var creationConfirmationIsPresented:
        Binding<Bool>
    {
        Binding {
            creationModel?
                .showsConfirmation
                == true
        } set: { isPresented in
            if !isPresented {
                creationModel?
                    .dismissConfirmation()
            }
        }
    }

    private var creationFailureIsPresented:
        Binding<Bool>
    {
        Binding {
            creationModel?.failure != nil
        } set: { isPresented in
            if !isPresented {
                creationModel?
                    .dismissFailure()
            }
        }
    }

    private func prepareCreationModelIfNeeded() {
        guard creationModel == nil else {
            return
        }
        let pipelinesModel = model
        creationModel =
            GitLabMergeRequestPipelineCreationModel(
                accountID: accountID,
                route: pipelinesModel.route,
                apiAccess: apiAccess,
                service: actionService,
                isAccountCurrent:
                    isAccountCurrent,
                isMergeRequestOpen:
                    isMergeRequestOpen,
                reconcile: {
                    pipelinesModel
                        .reconcileCreatedPipeline(
                            $0
                        )
                },
                refresh: {
                    await pipelinesModel
                        .refresh()
                }
            )
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
        .listRowBackground(Color.clear)
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error =
                creationModel?
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
