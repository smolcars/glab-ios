#if DEBUG
    import SwiftUI

    struct GitLabTodoNotificationFixtureView:
        View
    {
        private let session =
            try! GitLabStoredSession(
                host:
                    GitLabHost(
                        "gitlab.example.com"
                    ),
                user:
                    GitLabUserSummary(
                        id: 42,
                        username: "octocat",
                        name: "The Octocat",
                        avatarURL: nil
                    ),
                oauthApplicationID:
                    "notification-fixture",
                personalAccessTokenMetadata: nil,
                credential:
                    GitLabCredential.oauth(
                        accessToken: "fixture-token",
                        refreshToken: nil,
                        expiresAt: nil
                    )
            )
        @State private var appSession =
            AppSession(
                credentialStore:
                    InMemoryGitLabCredentialStore()
            )

        var body: some View {
            AccountView(
                session: session,
                appSession: appSession
            )
            .task {
                try? await appSession
                    .establish(session)
            }
        }
    }
#endif
