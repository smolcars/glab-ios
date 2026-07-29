import SwiftUI

private enum HomeNavigationRoute: Hashable {
    case search
}

enum HomeSheetDestination: Identifiable {
    enum ID: Hashable {
        case account
        case issueCreation(
            ObjectIdentifier
        )
    }

    case account
    case issueCreation(
        GitLabIssueCreationPresentation
    )

    var id: ID {
        switch self {
        case .account:
            .account
        case let .issueCreation(
            presentation
        ):
            .issueCreation(
                presentation.id
            )
        }
    }
}

typealias HomeSheetPresentationState =
    GitLabPreparedSheetPresentationState<
        HomeSheetDestination
    >

struct HomeView: View {
    let session: GitLabStoredSession
    let accountID: GitLabAccountID
    let appSession: AppSession
    let model: HomeDashboardModel
    let assignedIssuesModel: AssignedIssuesModel
    let assignedMergeRequestsModel:
        MergeRequestsModel
    let reviewRequestsModel:
        MergeRequestsModel
    let issueLoader: any GitLabIssueLoading
    let mergeRequestLoader:
        any GitLabMergeRequestLoading
            & GitLabMergeRequestApprovalLoading
            & GitLabMergeRequestDiffLoading
            & GitLabMergeRequestDiffSummaryLoading
    let mergeRequestApprovalService:
        any GitLabMergeRequestApprovalServing
    let mergeRequestMergeService:
        any GitLabMergeRequestMergeServing
    let pipelineLoader:
        any GitLabPipelineLoading
    let discussionLoader:
        any GitLabDiscussionLoading
    let discussionMutator:
        any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let editService:
        any GitLabResourceEditing
    let issueStatusService:
        any GitLabIssueStatusServing
    let issueCreationService:
        any GitLabIssueCreationServing
    let projectLoader:
        any GitLabProjectLoading
            & GitLabProjectResolving
    let searchModel: GitLabGlobalSearchModel
    let incomingRoute: GitLabNativeRoute?
    let onResourceEdited:
        (GitLabResourceEditResult) -> Void
    let didOpenIncomingRoute: () -> Void

    @State private var path = NavigationPath()
    @State private var
        sheetPresentation =
        HomeSheetPresentationState()
    @State private var
        createdIssueRoute:
        GitLabIssueRoute?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if session.apiAccess == .readOnly {
                    Section {
                        readOnlyCallout
                    }
                }

                Section {
                    if model.hasTotalWorkFailure {
                        GitLabRetryStateView(
                            message:
                                "Your GitLab work could not be loaded. "
                                + "Check your connection and try again."
                        ) {
                            Task {
                                await refreshDashboard()
                            }
                        }
                        .frame(minHeight: 280)
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                    } else {
                        ForEach(HomeDashboardSection.allCases, id: \.self) {
                            section in
                            NavigationLink(value: section) {
                                HomeWorkShortcutRow(
                                    section: section,
                                    presentation: model.presentation(
                                        for: section
                                    )
                                )
                            }
                            .accessibilityIdentifier(
                                "home.shortcut.\(section.rawValue)"
                            )
                        }
                    }
                } header: {
                    Text("My Work")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .textCase(nil)
                        .padding(.bottom, 4)
                }
                .headerProminence(.increased)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: HomeDashboardSection.self) {
                section in
                destination(for: section)
            }
            .navigationDestination(
                for: GitLabNativeRoute.self
            ) {
                nativeDestination(for: $0)
            }
            .navigationDestination(
                for: HomeNavigationRoute.self
            ) { route in
                switch route {
                case .search:
                    GitLabGlobalSearchView(
                        model: searchModel,
                        accountID: accountID,
                        appSession: appSession
                    )
                }
            }
            .refreshable {
                await refreshDashboard()
            }
            .task {
                await loadDashboard()
            }
            .task(id: incomingRoute) {
                guard let incomingRoute else {
                    return
                }

                path.append(incomingRoute)
                didOpenIncomingRoute()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        sheetPresentation
                            .prepare(
                                .account
                            )
                    } label: {
                        GitLabUserAvatar(
                            user: displayedUser,
                            size: 44
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(.circle)
                    .accessibilityLabel(
                        "Account for \(displayedUser.displayName)"
                    )
                    .accessibilityHint("Opens account settings.")
                    .accessibilityIdentifier("home.accountButton")
                }

                ToolbarItemGroup(
                    placement: .topBarTrailing
                ) {
                    Button {
                        path.append(
                            HomeNavigationRoute
                                .search
                        )
                    } label: {
                        Image(
                            systemName:
                                "magnifyingglass"
                        )
                    }
                    .accessibilityLabel(
                        "Search GitLab"
                    )
                    .accessibilityHint(
                        "Searches projects, issues, "
                            + "and merge requests."
                    )
                    .accessibilityIdentifier(
                        "home.searchButton"
                    )

                    Button {
                        launchIssueCreation()
                    } label: {
                        Image(
                            systemName:
                                "square.and.pencil"
                        )
                    }
                    .accessibilityLabel(
                        "New issue"
                    )
                    .accessibilityHint(
                        "Opens the issue composer."
                    )
                    .accessibilityIdentifier(
                        "home.newIssueButton"
                    )
                }
            }
        }
        .sheet(
            isPresented:
                sheetIsPresented,
            onDismiss: {
                sheetPresentation
                    .didDismiss()
            }
        ) {
            if
                let destination =
                    sheetPresentation
                    .destination
            {
                sheetContent(
                    for: destination
                )
                .presentationDragIndicator(
                    .visible
                )
            }
        }
        .onChange(
            of:
                sheetPresentation
                .preparedID
        ) { _, preparedID in
            sheetPresentation
                .presentPrepared(
                    id: preparedID
                )
        }
        .onChange(of: createdIssueRoute) {
            _, route in
            guard let route else {
                return
            }
            sheetPresentation.dismiss()
            path.append(
                GitLabNativeRoute.issue(
                    route
                )
            )
            createdIssueRoute = nil
        }
    }

    @MainActor
    private func launchIssueCreation() {
        let model =
            GitLabIssueCreationModel(
                accountID: accountID,
                apiAccess:
                    session.apiAccess,
                service:
                    issueCreationService,
                draftStore:
                    appSession
                    .issueCreationDraftStore,
                isAccountCurrent: {
                    appSession
                        .activeAccountID
                        == accountID
                }
            ) { issue in
                createdIssueRoute =
                    issue.route
            }
        sheetPresentation.prepare(
            .issueCreation(
                GitLabIssueCreationPresentation(
                    model: model
                )
            )
        )
    }

    private var sheetIsPresented:
        Binding<Bool>
    {
        Binding {
            sheetPresentation
                .isPresented
        } set: { isPresented in
            guard !isPresented else {
                return
            }
            sheetPresentation.dismiss()
        }
    }

    @ViewBuilder
    private func sheetContent(
        for destination:
            HomeSheetDestination
    ) -> some View {
        switch destination {
        case .account:
            AccountView(
                session: session,
                appSession: appSession
            )
        case let .issueCreation(
            presentation
        ):
            GitLabIssueCreationView(
                model: presentation.model,
                accountID: accountID,
                appSession: appSession
            )
        }
    }

    @ViewBuilder
    private func nativeDestination(
        for route: GitLabNativeRoute
    ) -> some View {
        switch route {
        case let .project(projectRoute):
            GitLabProjectDetailView(
                route: projectRoute,
                loader: projectLoader,
                apiAccess:
                    session.apiAccess,
                issueLoader:
                    issueLoader,
                discussionLoader:
                    discussionLoader,
                discussionMutator:
                    discussionMutator,
                reactionService:
                    reactionService,
                editService:
                    editService,
                issueStatusService:
                    issueStatusService,
                issueCreationService:
                    issueCreationService,
                accountID: accountID,
                appSession: appSession,
                onResourceEdited:
                    onResourceEdited
            )
        case let .issue(issueRoute):
            GitLabIssueDetailView(
                route: issueRoute,
                loader: issueLoader,
                discussionLoader:
                    discussionLoader,
                discussionMutator:
                    discussionMutator,
                reactionService:
                    reactionService,
                editService:
                    editService,
                issueStatusService:
                    issueStatusService,
                accountID: accountID,
                appSession: appSession,
                onResourceEdited:
                    onResourceEdited
            )
        case let .mergeRequest(
            mergeRequestRoute
        ):
            GitLabMergeRequestDetailView(
                route: mergeRequestRoute,
                loader: mergeRequestLoader,
                approvalService:
                    mergeRequestApprovalService,
                mergeService:
                    mergeRequestMergeService,
                pipelineLoader:
                    pipelineLoader,
                discussionLoader:
                    discussionLoader,
                discussionMutator:
                    discussionMutator,
                reactionService:
                    reactionService,
                editService:
                    editService,
                accountID: accountID,
                appSession: appSession,
                onResourceEdited:
                    onResourceEdited
            )
        }
    }

    private var readOnlyCallout: some View {
        Label {
            Text("Read-only access. Changes are disabled.")
        } icon: {
            Image(systemName: "eye.fill")
        }
        .font(.callout)
        .foregroundStyle(.orange)
        .accessibilityLabel(
            "This token is read-only. Actions such as completing "
                + "Todos will be disabled."
        )
        .listRowBackground(Color.orange.opacity(0.1))
    }

    private var displayedUser: GitLabUserSummary {
        guard let user = model.user else {
            return session.user
        }

        return GitLabUserSummary(
            id: user.id,
            username: user.username,
            name: user.name,
            avatarURL: user.avatarURL
        )
    }

    @ViewBuilder
    private func destination(
        for section: HomeDashboardSection
    ) -> some View {
        switch section {
        case .assignedIssues:
            AssignedIssuesView(
                model: assignedIssuesModel,
                loader: issueLoader,
                discussionLoader: discussionLoader,
                discussionMutator:
                    discussionMutator,
                reactionService:
                    reactionService,
                editService:
                    editService,
                issueStatusService:
                    issueStatusService,
                accountID: accountID,
                appSession: appSession,
                onResourceEdited:
                    onResourceEdited
            )
        case .assignedMergeRequests:
            MergeRequestsView(
                mode: .assigned,
                model:
                    assignedMergeRequestsModel,
                loader: mergeRequestLoader,
                approvalService:
                    mergeRequestApprovalService,
                mergeService:
                    mergeRequestMergeService,
                pipelineLoader:
                    pipelineLoader,
                discussionLoader: discussionLoader,
                discussionMutator:
                    discussionMutator,
                reactionService:
                    reactionService,
                editService:
                    editService,
                accountID: accountID,
                appSession: appSession,
                onResourceEdited:
                    onResourceEdited
            )
        case .reviewRequests:
            MergeRequestsView(
                mode: .reviewRequested,
                model:
                    reviewRequestsModel,
                loader: mergeRequestLoader,
                approvalService:
                    mergeRequestApprovalService,
                mergeService:
                    mergeRequestMergeService,
                pipelineLoader:
                    pipelineLoader,
                discussionLoader: discussionLoader,
                discussionMutator:
                    discussionMutator,
                reactionService:
                    reactionService,
                editService:
                    editService,
                accountID: accountID,
                appSession: appSession,
                onResourceEdited:
                    onResourceEdited
            )
        case .recentProjects:
            ProjectsView(
                mode: .recent,
                loader: projectLoader,
                accountID: accountID,
                appSession: appSession
            )
        case .starredProjects:
            ProjectsView(
                mode: .starred,
                loader: projectLoader,
                accountID: accountID,
                appSession: appSession
            )
        }
    }

    private func loadDashboard() async {
        await model.loadIfNeeded()
        await handleAuthenticationFailure()
    }

    private func refreshDashboard() async {
        await model.refresh()
        await handleAuthenticationFailure()
    }

    private func handleAuthenticationFailure() async {
        guard let error = model.authenticationFailure else {
            return
        }

        await appSession.handleAuthenticationFailure(
            error,
            for: accountID
        )
    }
}
