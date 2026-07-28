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

    private let accountID: GitLabAccountID
    @State private var selectedTab = GitLabAppTab.defaultTab
    @State private var homeDashboardModel: HomeDashboardModel
    @State private var assignedIssuesModel: AssignedIssuesModel
    @State private var todosModel: TodosModel
    private let issueLoader: any GitLabIssueLoading
    private let mergeRequestLoader:
        any GitLabMergeRequestLoading
    private let discussionLoader:
        any GitLabDiscussionLoading
    private let projectLoader: any GitLabProjectLoading
    private let markdownRenderer:
        any GitLabMarkdownRendering
    private let markdownImageLoader:
        any GitLabMarkdownImageLoading

    init(
        session: GitLabStoredSession,
        appSession: AppSession
    ) {
        self.session = session
        self.appSession = appSession
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
        let projectLoader = LiveGitLabProjectLoader(
            client: client
        )
        let discussionLoader =
            LiveGitLabDiscussionLoader(
                client: client
            )
        let todoService = LiveGitLabTodoLoader(
            client: client
        )
        self.issueLoader = issueLoader
        self.mergeRequestLoader = mergeRequestLoader
        self.discussionLoader = discussionLoader
        self.projectLoader = projectLoader
        markdownRenderer = GitLabMarkdownRenderer()
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
        _todosModel = State(
            initialValue: TodosModel(
                loader: todoService,
                mutator: todoService,
                apiAccess: session.apiAccess
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
                    issueLoader: issueLoader,
                    mergeRequestLoader: mergeRequestLoader,
                    discussionLoader: discussionLoader,
                    projectLoader: projectLoader
                )
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
                    discussionLoader:
                        discussionLoader,
                    accountID: accountID,
                    appSession: appSession
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
        .accessibilityIdentifier("signedIn.tabView")
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
