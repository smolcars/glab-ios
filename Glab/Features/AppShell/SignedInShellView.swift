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
        _homeDashboardModel = State(
            initialValue: HomeDashboardModel(
                loader: LiveHomeDashboardLoader(
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
                    model: homeDashboardModel
                )
            }

            Tab(
                GitLabAppTab.todos.title,
                systemImage: GitLabAppTab.todos.systemImage,
                value: GitLabAppTab.todos
            ) {
                TodosView()
            }
        }
        .tint(.orange)
        .accessibilityIdentifier("signedIn.tabView")
    }
}
