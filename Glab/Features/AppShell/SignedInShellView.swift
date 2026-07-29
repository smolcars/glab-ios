import SwiftUI

nonisolated enum GitLabAppTab:
    String,
    CaseIterable,
    Equatable,
    Hashable,
    Sendable
{
    case home
    case todos

    static let defaultTab = Self.home

    var title: String {
        switch self {
        case .home:
            "Home"
        case .todos:
            "Todos"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house.fill"
        case .todos:
            "checklist"
        }
    }
}

struct SignedInShellView: View {
    let session: GitLabStoredSession
    let appSession: AppSession
    let incomingLinkModel:
        GitLabIncomingLinkModel

    private let accountID: GitLabAccountID
    @State private var selectedTab = GitLabAppTab.defaultTab
    @State private var homeDashboardModel: HomeDashboardModel
    @State private var assignedIssuesModel: AssignedIssuesModel
    @State private var assignedMergeRequestsModel:
        MergeRequestsModel
    @State private var reviewRequestsModel:
        MergeRequestsModel
    @State private var todosModel: TodosModel
    @State private var globalSearchModel:
        GitLabGlobalSearchModel
    @State private var deepLinkResolutionModel:
        GitLabDeepLinkResolutionModel
    @State private var incomingRoute:
        GitLabNativeRoute?
    private let issueLoader: any GitLabIssueLoading
    private let mergeRequestLoader:
        any GitLabMergeRequestLoading
            & GitLabMergeRequestApprovalLoading
            & GitLabMergeRequestDiffLoading
            & GitLabMergeRequestDiffSummaryLoading
    private let mergeRequestApprovalService:
        any GitLabMergeRequestApprovalServing
    private let pipelineLoader:
        any GitLabPipelineLoading
    private let pipelineActionService:
        any GitLabPipelineActionServing
    private let jobTraceLoader:
        any GitLabJobTraceLoading
    private let discussionLoader:
        any GitLabDiscussionLoading
    private let discussionMutator:
        any GitLabDiscussionMutating
    private let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    private let resourceEditService:
        any GitLabResourceEditing
    private let issueStatusService:
        any GitLabIssueStatusServing
    private let issueCreationService:
        any GitLabIssueCreationServing
    private let projectLoader:
        any GitLabProjectLoading
            & GitLabProjectResolving
    private let markdownRenderer:
        any GitLabMarkdownRendering
    private let markdownImageLoader:
        any GitLabMarkdownImageLoading
    private let diffRenderer:
        any GitLabDiffRendering

    init(
        session: GitLabStoredSession,
        appSession: AppSession,
        incomingLinkModel:
            GitLabIncomingLinkModel
    ) {
        self.session = session
        self.appSession = appSession
        self.incomingLinkModel =
            incomingLinkModel
        let accountID = GitLabAccountID(session: session)
        self.accountID = accountID

        let transport = URLSessionGitLabHTTPTransport()
        let client = GitLabSessionClient(
            session: session,
            transport: transport,
            tokenExchanger: GitLabOAuthTokenClient(
                transport: transport
            ),
            credentialStore: appSession.credentialStore,
            responseCache: appSession.responseCache,
            sessionDidRefresh: { refreshedSession in
                await appSession.synchronizeRefreshedSession(
                    refreshedSession,
                    for: accountID
                )
            }
        )
        let issueLoader = LiveGitLabIssueLoader(
            client: client
        )
        let mergeRequestLoader =
            LiveGitLabMergeRequestLoader(
                client: client
            )
        let mergeRequestApprovalService =
            LiveGitLabMergeRequestApprovalService(
                client: client
            )
        let pipelineLoader =
            LiveGitLabPipelineLoader(
                client: client
            )
        let pipelineActionService =
            LiveGitLabPipelineActionService(
                client: client
            )
        let jobTraceLoader:
            any GitLabJobTraceLoading
        if
            let jobTraceStore =
                appSession.jobTraceStore
                as? any
                    GitLabJobTraceImportStoring
        {
            jobTraceLoader =
                LiveGitLabJobTraceLoader(
                    session: client,
                    store: jobTraceStore
                )
        } else {
            jobTraceLoader =
                UnavailableGitLabJobTraceLoader()
        }
        let projectLoader = LiveGitLabProjectLoader(
            client: client
        )
        let discussionLoader =
            LiveGitLabDiscussionService(
                client: client
            )
        let reactionService =
            LiveGitLabEmojiReactionService(
                client: client
            )
        let resourceEditService =
            LiveGitLabResourceEditService(
                client: client
            )
        let issueStatusService =
            LiveGitLabIssueStatusService(
                client: client,
                apiAccess:
                    session.apiAccess
            )
        let issueCreationService =
            LiveGitLabIssueCreationService(
                client: client
            )
        let todoService = LiveGitLabTodoLoader(
            client: client
        )
        self.issueLoader = issueLoader
        self.mergeRequestLoader = mergeRequestLoader
        self.mergeRequestApprovalService =
            mergeRequestApprovalService
        self.pipelineLoader = pipelineLoader
        self.pipelineActionService =
            pipelineActionService
        self.jobTraceLoader =
            jobTraceLoader
        self.discussionLoader = discussionLoader
        discussionMutator = discussionLoader
        self.reactionService =
            reactionService
        self.resourceEditService =
            resourceEditService
        self.issueStatusService =
            issueStatusService
        self.issueCreationService =
            issueCreationService
        self.projectLoader = projectLoader
        markdownRenderer = GitLabMarkdownRenderer()
        diffRenderer = GitLabDiffRenderer()
        let imageRequestPolicy =
            GitLabMarkdownImageRequestPolicy(
                host: session.host,
                authorization:
                    session.credential
                        .authorization
            )
        markdownImageLoader =
            GitLabMarkdownImageLoader(
                accountID: accountID,
                requestPolicy:
                    imageRequestPolicy,
                transport:
                    URLSessionGitLabMarkdownImageTransport(
                        requestPolicy:
                            imageRequestPolicy
                    )
            )
        _homeDashboardModel = State(
            initialValue: HomeDashboardModel(
                loader: LiveHomeDashboardLoader(
                    client: client
                )
            )
        )
        _assignedIssuesModel = State(
            initialValue: AssignedIssuesModel(
                loader: issueLoader
            )
        )
        _assignedMergeRequestsModel = State(
            initialValue: MergeRequestsModel(
                mode: .assigned,
                loader: mergeRequestLoader
            )
        )
        _reviewRequestsModel = State(
            initialValue: MergeRequestsModel(
                mode: .reviewRequested,
                loader: mergeRequestLoader
            )
        )
        _todosModel = State(
            initialValue: TodosModel(
                loader: todoService,
                mutator: todoService,
                apiAccess: session.apiAccess
            )
        )
        _globalSearchModel = State(
            initialValue:
                GitLabGlobalSearchModel(
                    accountID: accountID,
                    loader:
                        LiveGitLabSearchLoader(
                            client: client
                        )
                )
        )
        _deepLinkResolutionModel = State(
            initialValue:
                GitLabDeepLinkResolutionModel(
                    accountID: accountID,
                    resolver:
                        GitLabDeepLinkRouteResolver(
                            projectLoader:
                                projectLoader
                        )
                )
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: GitLabAppTab.home) {
                HomeView(
                    session: session,
                    accountID: accountID,
                    appSession: appSession,
                    model: homeDashboardModel,
                    assignedIssuesModel: assignedIssuesModel,
                    assignedMergeRequestsModel:
                        assignedMergeRequestsModel,
                    reviewRequestsModel:
                        reviewRequestsModel,
                    issueLoader: issueLoader,
                    mergeRequestLoader: mergeRequestLoader,
                    mergeRequestApprovalService:
                        mergeRequestApprovalService,
                    pipelineLoader:
                        pipelineLoader,
                    discussionLoader: discussionLoader,
                    discussionMutator:
                        discussionMutator,
                    reactionService:
                        reactionService,
                    editService:
                        resourceEditService,
                    issueStatusService:
                        issueStatusService,
                    issueCreationService:
                        issueCreationService,
                    projectLoader: projectLoader,
                    searchModel:
                        globalSearchModel,
                    incomingRoute:
                        incomingRoute,
                    onResourceEdited:
                        reconcileEditedResource
                ) {
                    incomingRoute = nil
                    incomingLinkModel.clear()
                }
            } label: {
                Label(
                    GitLabAppTab.home.title,
                    systemImage:
                        GitLabAppTab.home.systemImage
                )
                .accessibilityIdentifier("tab.home")
            }

            Tab(value: GitLabAppTab.todos) {
                TodosView(
                    model: todosModel,
                    issueLoader: issueLoader,
                    mergeRequestLoader:
                        mergeRequestLoader,
                    mergeRequestApprovalService:
                        mergeRequestApprovalService,
                    pipelineLoader:
                        pipelineLoader,
                    discussionLoader:
                        discussionLoader,
                    discussionMutator:
                        discussionMutator,
                    reactionService:
                        reactionService,
                    editService:
                        resourceEditService,
                    issueStatusService:
                        issueStatusService,
                    accountID: accountID,
                    appSession: appSession,
                    onResourceEdited:
                        reconcileEditedResource
                )
            } label: {
                Label(
                    GitLabAppTab.todos.title,
                    systemImage:
                        GitLabAppTab.todos.systemImage
                )
                .accessibilityIdentifier("tab.todos")
            }
            .badge(todosModel.pendingBadgeCount ?? 0)
        }
        .tint(.orange)
        .environment(
            \.gitLabMarkdownRenderer,
            markdownRenderer
        )
        .environment(
            \.gitLabMarkdownImageLoader,
            markdownImageLoader
        )
        .environment(
            \.gitLabMarkdownLinkHandler,
            GitLabMarkdownLinkHandler {
                url in
                guard
                    appSession.accounts
                        .contains(where: {
                            GitLabInAppLinkRouting
                                .shouldHandle(
                                    url,
                                    for: $0.host
                                )
                        })
                else {
                    return false
                }

                return incomingLinkModel
                    .receive(
                        url,
                        accounts:
                            appSession.accounts
                                .map(\.id),
                        activeAccountID:
                            appSession
                                .activeAccountID
                    )
            }
        )
        .environment(
            \.gitLabDiffRenderer,
            diffRenderer
        )
        .environment(
            \.gitLabJobTraceLoader,
            jobTraceLoader
        )
        .environment(
            \.gitLabPipelineActionService,
            pipelineActionService
        )
        .accessibilityIdentifier("signedIn.tabView")
        .task(
            id: incomingLinkModel.decision
        ) {
            await handleIncomingLink()
        }
        .alert(
            "GitLab Session Ended",
            isPresented:
                authenticationNoticeIsPresented
        ) {
            Button("OK") {
                appSession
                    .dismissAuthenticationNotice()
            }
        } message: {
            Text(
                appSession.authenticationNotice?
                    .description
                    ?? ""
            )
        }
    }

    private func handleIncomingLink() async {
        guard
            case let .open(
                expectedAccountID,
                target,
                sourceURL
            ) = incomingLinkModel.decision,
            expectedAccountID == accountID
        else {
            deepLinkResolutionModel.cancel()
            return
        }

        await deepLinkResolutionModel.resolve(
            target,
            for: expectedAccountID,
            sourceURL: sourceURL
        )
        guard !Task.isCancelled else {
            return
        }

        switch deepLinkResolutionModel.state {
        case let .resolved(
            route,
            resolvedSourceURL
        ):
            guard
                incomingLinkModel.pendingURL
                    == resolvedSourceURL,
                case let .open(
                    currentAccountID,
                    _,
                    currentSourceURL
                ) = incomingLinkModel
                    .decision,
                currentAccountID == accountID,
                currentSourceURL
                    == resolvedSourceURL
            else {
                return
            }

            selectedTab = .home
            await Task.yield()
            incomingRoute = route
        case let .failed(
            failedSourceURL,
            error
        ):
            if error.requiresReauthentication {
                incomingLinkModel
                    .preserveForAccountTransition()
                await appSession
                    .handleAuthenticationFailure(
                        error,
                        for: accountID
                    )
            } else {
                incomingLinkModel
                    .offerBrowserFallback(
                        for: failedSourceURL
                    )
            }
        case .idle, .resolving:
            break
        }
    }

    private func reconcileEditedResource(
        _ result: GitLabResourceEditResult
    ) {
        let removedHomePreview =
            homeDashboardModel
                .reconcileEditedResource(
                    result,
                    currentUserID:
                        accountID.userID
                )
        todosModel
            .reconcileEditedResource(result)
        globalSearchModel
            .reconcileEditedResource(
                result,
                for: accountID
            )

        if case let .issue(issue) = result {
            let remainsAssigned =
                issue.isAssignedOpenWork(
                    for: accountID.userID
                )
            let wasPresent =
                assignedIssuesModel
                .reconcileAssignedIssue(
                    issue,
                    currentUserID:
                        accountID.userID
                )
            let removed =
                !remainsAssigned
                && wasPresent
            if removed {
                Task {
                    await assignedIssuesModel
                        .refresh()
                }
            }
        }

        if
            case let .mergeRequest(
                mergeRequest
            ) = result
        {
            let remainsAssigned =
                mergeRequest.isOpenWork(
                    for: .assigned,
                    userID: accountID.userID
                )
            let wasInAssigned =
                assignedMergeRequestsModel
                    .reconcileMergeRequest(
                        mergeRequest,
                        mode: .assigned,
                        currentUserID:
                            accountID.userID
                    )
            let removedAssigned =
                !remainsAssigned
                && wasInAssigned

            let remainsReviewRequested =
                mergeRequest.isOpenWork(
                    for: .reviewRequested,
                    userID: accountID.userID
                )
            let wasInReviewRequests =
                reviewRequestsModel
                    .reconcileMergeRequest(
                        mergeRequest,
                        mode: .reviewRequested,
                        currentUserID:
                            accountID.userID
                    )
            let removedReviewRequested =
                !remainsReviewRequested
                && wasInReviewRequests

            if
                removedAssigned
                    || removedReviewRequested
            {
                Task {
                    if removedAssigned {
                        await assignedMergeRequestsModel
                            .refresh()
                    }
                    if removedReviewRequested {
                        await reviewRequestsModel
                            .refresh()
                    }
                }
            }
        }

        if removedHomePreview {
            Task {
                await homeDashboardModel
                    .refresh()
            }
        }
    }

    private var authenticationNoticeIsPresented:
        Binding<Bool>
    {
        Binding {
            appSession.authenticationNotice != nil
        } set: { isPresented in
            if !isPresented {
                appSession
                    .dismissAuthenticationNotice()
            }
        }
    }
}
