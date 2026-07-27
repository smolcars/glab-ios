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
            SignedInHomeView(
                session: session,
                appSession: appSession
            )
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

#Preview("Restoring") {
    AppRootView()
        .environment(
            AppSession(
                credentialStore: InMemoryGitLabCredentialStore()
            )
        )
}
