import SwiftUI

struct HomeView: View {
    let session: GitLabStoredSession
    let appSession: AppSession
    let model: HomeDashboardModel

    @State private var path = NavigationPath()
    @State private var showsAccount = false

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
                HomeDashboardListView(
                    section: section,
                    model: model,
                    refresh: refreshDashboard
                )
            }
            .refreshable {
                await refreshDashboard()
            }
            .task {
                await loadDashboard()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsAccount = true
                    } label: {
                        GitLabUserAvatar(
                            user: displayedUser,
                            size: 30
                        )
                    }
                    .accessibilityLabel(
                        "Account for \(displayName)"
                    )
                    .accessibilityIdentifier("home.accountButton")
                }
            }
            .sheet(isPresented: $showsAccount) {
                AccountView(
                    session: session,
                    appSession: appSession
                )
                .presentationDragIndicator(.visible)
            }
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

    private var displayName: String {
        let name = displayedUser.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return name.isEmpty ? displayedUser.username : name
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

        await appSession.handleAuthenticationFailure(error)
    }
}
