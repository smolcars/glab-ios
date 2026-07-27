nonisolated struct GitLabPrivacyAndAccessPresentation:
    Equatable,
    Sendable
{
    static let oauthSignIn = Self(
        credentialKind: .oauth,
        apiAccess: .readWrite
    )

    let scopeName: String
    let scopeSummary: String
    let authenticationSummary: String
    let storageSummary: String
    let dataUseSummary: String

    init(session: GitLabStoredSession) {
        self.init(
            credentialKind: session.credentialKind,
            apiAccess: session.apiAccess
        )
    }

    init(
        credentialKind: GitLabCredentialKind,
        apiAccess: GitLabAPIAccess
    ) {
        switch apiAccess {
        case .readOnly:
            scopeName = "read_api"
            scopeSummary =
                "The read_api scope is read-only. You can browse "
                + "GitLab, but actions such as completing Todos "
                + "are disabled."
        case .readWrite:
            scopeName = "api"
            scopeSummary =
                "GitLab’s api scope grants read and write access. "
                + "Glab uses it to show your work and complete "
                + "Todos; the current app does not create, edit, "
                + "merge, or delete projects and issues."
        }

        switch credentialKind {
        case .oauth:
            authenticationSummary =
                "GitLab handles your password, 2FA, and SSO on "
                + "its secure web page. Glab receives OAuth "
                + "tokens, never your GitLab password."
            storageSummary =
                "OAuth access and refresh tokens are stored in "
                + "the iOS Keychain."
        case .personalAccessToken:
            authenticationSummary =
                "The personal access token authenticates API "
                + "requests instead of your GitLab password."
            storageSummary =
                "Your personal access token is stored in the "
                + "iOS Keychain."
        }

        dataUseSummary =
            "Glab has no analytics. API requests go to the "
            + "GitLab instance you choose, and credentials are "
            + "never attached to avatar images or links opened "
            + "outside the app."
    }
}
