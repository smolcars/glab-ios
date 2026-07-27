import SwiftUI

struct HomeView: View {
    let session: GitLabStoredSession
    let appSession: AppSession

    @State private var path = NavigationPath()
    @State private var showsAccount = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if session.apiAccess == .readOnly {
                        readOnlyCallout
                    }

                    Text("My Work")
                        .font(.title2.bold())

                    GitLabEmptyStateView(
                        title: "Your work will appear here",
                        message:
                            "Assigned issues, merge requests, and projects "
                            + "will be collected in this space.",
                        systemImage: "square.stack.3d.up"
                    )
                    .frame(minHeight: 300)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsAccount = true
                    } label: {
                        GitLabUserAvatar(
                            user: session.user,
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
            Text(
                "This token is read-only. Actions such as completing "
                    + "Todos will be disabled."
            )
        } icon: {
            Image(systemName: "eye.fill")
        }
        .font(.callout)
        .foregroundStyle(.orange)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.1),
            in: .rect(cornerRadius: 16)
        )
    }

    private var displayName: String {
        let name = session.user.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return name.isEmpty ? session.user.username : name
    }
}
