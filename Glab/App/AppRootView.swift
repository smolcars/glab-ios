import SwiftUI

struct AppRootView: View {
    @Environment(AppSession.self) private var appSession

    var body: some View {
        switch appSession.state {
        case .restoring:
            restoringView
        case .signedOut:
            GitLabOAuthSignInScene(
                appSession: appSession,
                authenticationMessage:
                    appSession.authenticationNotice?.description
            )
        case let .failed(error):
            GitLabOAuthSignInScene(
                appSession: appSession,
                authenticationMessage:
                    appSession.authenticationNotice?.description
                    ?? error.description
            )
        case let .signedIn(session):
            SignedInShellView(
                session: session,
                appSession: appSession
            )
            .id(GitLabAccountID(session: session))
        }
    }

    private var restoringView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            ProgressView("Restoring GitLab session…")
        }
        .gitLabAccessibilityAnnouncement(
            "Restoring GitLab session"
        )
        .accessibilityIdentifier("app.restoringSession")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
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
