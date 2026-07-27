import Testing
@testable import Glab

@Suite("GitLab privacy and access presentation")
struct GitLabPrivacyAndAccessPresentationTests {
    @Test("Explains OAuth API access before sign-in")
    func explainsOAuthAccess() {
        let presentation =
            GitLabPrivacyAndAccessPresentation.oauthSignIn

        #expect(presentation.scopeName == "api")
        #expect(
            presentation.scopeSummary.contains(
                "read and write"
            )
        )
        #expect(
            presentation.scopeSummary.contains(
                "complete Todos"
            )
        )
        #expect(
            presentation.authenticationSummary.contains(
                "password, 2FA, and SSO"
            )
        )
        #expect(
            presentation.storageSummary.contains(
                "iOS Keychain"
            )
        )
        #expect(
            presentation.dataUseSummary.contains(
                "no analytics"
            )
        )
    }

    @Test("Explains a read-only personal access token")
    func explainsReadOnlyToken() {
        let presentation =
            GitLabPrivacyAndAccessPresentation(
                credentialKind: .personalAccessToken,
                apiAccess: .readOnly
            )

        #expect(presentation.scopeName == "read_api")
        #expect(
            presentation.scopeSummary.contains(
                "read-only"
            )
        )
        #expect(
            presentation.scopeSummary.contains(
                "disabled"
            )
        )
        #expect(
            presentation.storageSummary.contains(
                "personal access token"
            )
        )
    }

    @Test("Explains a write-enabled personal access token")
    func explainsReadWriteToken() {
        let presentation =
            GitLabPrivacyAndAccessPresentation(
                credentialKind: .personalAccessToken,
                apiAccess: .readWrite
            )

        #expect(presentation.scopeName == "api")
        #expect(
            presentation.scopeSummary.contains(
                "complete Todos"
            )
        )
    }

    @Test("Links to the public Glab privacy policy")
    func linksToPrivacyPolicy() throws {
        let url = try #require(
            GitLabPrivacyAndAccessPresentation
                .oauthSignIn
                .privacyPolicyURL
        )

        #expect(url.scheme == "https")
        #expect(url.host == "github.com")
        #expect(url.path.hasSuffix("/PRIVACY.md"))
    }

    @Test("Presentation cannot contain a credential value")
    func excludesCredentialValues() throws {
        let secret = "never-render-this-token"
        let session = try GitLabStoredSession(
            host: GitLabHost("gitlab.com"),
            user: GitLabUserSummary(
                id: 7,
                username: "octo",
                name: "Octo",
                avatarURL: nil
            ),
            oauthApplicationID: "application-id",
            personalAccessTokenMetadata: nil,
            credential: GitLabCredential.oauth(
                accessToken: secret,
                refreshToken: "refresh-\(secret)",
                expiresAt: nil
            )
        )
        let presentation =
            GitLabPrivacyAndAccessPresentation(
                session: session
            )
        let renderedCopy = [
            presentation.scopeName,
            presentation.scopeSummary,
            presentation.authenticationSummary,
            presentation.storageSummary,
            presentation.dataUseSummary,
        ].joined(separator: " ")

        #expect(!renderedCopy.contains(secret))
    }
}
