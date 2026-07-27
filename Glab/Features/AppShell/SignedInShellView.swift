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

    @State private var selectedTab = GitLabAppTab.defaultTab
    @State private var homeDashboardModel: HomeDashboardModel
    @State private var assignedIssuesModel: AssignedIssuesModel
    @State private var todosModel: TodosModel
    private let issueLoader: any GitLabIssueLoading
    private let mergeRequestLoader:
        any GitLabMergeRequestLoading
    private let projectLoader: any GitLabProjectLoading

    init(
        session: GitLabStoredSession,
        appSession: AppSession
    ) {
        self.session = session
        self.appSession = appSession

        let transport = URLSessionGitLabHTTPTransport()
        let client = GitLabSessionClient(
            session: session,
            transport: transport,
            tokenExchanger: GitLabOAuthTokenClient(
                transport: transport
            ),
            credentialStore: appSession.credentialStore,
            sessionDidRefresh: { refreshedSession in
                await appSession.synchronizeRefreshedSession(
                    refreshedSession
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
        self.issueLoader = issueLoader
        self.mergeRequestLoader = mergeRequestLoader
        self.projectLoader = projectLoader
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
                loader: LiveGitLabTodoLoader(
                    client: client
                )
            )
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(
                GitLabAppTab.home.title,
                systemImage: GitLabAppTab.home.systemImage,
                value: GitLabAppTab.home
            ) {
                HomeView(
                    session: session,
                    appSession: appSession,
                    model: homeDashboardModel,
                    assignedIssuesModel: assignedIssuesModel,
                    issueLoader: issueLoader,
                    mergeRequestLoader: mergeRequestLoader,
                    projectLoader: projectLoader
                )
            }

            Tab(
                GitLabAppTab.todos.title,
                systemImage: GitLabAppTab.todos.systemImage,
                value: GitLabAppTab.todos
            ) {
                TodosView(
                    model: todosModel,
                    issueLoader: issueLoader,
                    mergeRequestLoader:
                        mergeRequestLoader,
                    appSession: appSession
                )
            }
            .badge(todosModel.pendingBadgeCount ?? 0)
        }
        .tint(.orange)
        .accessibilityIdentifier("signedIn.tabView")
    }
}
