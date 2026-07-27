import SwiftUI

struct AppRootView: View {
    @Environment(AppSession.self) private var appSession

    var body: some View {
        switch appSession.state {
        case .restoring:
            restoringView
        case .signedOut, .failed:
            PersonalAccessTokenSignInScene(appSession: appSession)
        case let .signedIn(session):
            SignedInPlaceholderView(session: session)
        }
    }

    private var restoringView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.orange)
            ProgressView("Restoring GitLab session…")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct SignedInPlaceholderView: View {
    let session: GitLabStoredSession

    var body: some View {
        let instanceName = session.host.siteURL.host(percentEncoded: false)
            ?? session.host.siteURL.absoluteString

        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("GitLab connected")
                        .font(.title2.bold())
                    Text(
                        "Signed in as @\(session.user.username) on "
                            + instanceName
                    )
                    .foregroundStyle(.secondary)
                }

                if session.apiAccess == .readOnly {
                    Label {
                        Text(
                            "This token is read-only. Create one with the api "
                                + "scope to complete Todos."
                        )
                    } icon: {
                        Image(systemName: "eye.fill")
                    }
                    .foregroundStyle(.orange)
                    .padding(16)
                    .background(
                        Color.orange.opacity(0.1),
                        in: .rect(cornerRadius: 16)
                    )
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Glab")
        }
    }
}

#Preview("Restoring") {
    AppRootView()
        .environment(
            AppSession(
                credentialStore: InMemoryGitLabCredentialStore()
            )
        )
}
