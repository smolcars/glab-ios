import Foundation
import Testing
@testable import Glab

@Suite("Stored GitLab session")
struct GitLabStoredSessionTests {
    @Test("Models OAuth metadata without exposing tokens")
    func modelsOAuthSession() throws {
        let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)
        let credential = try GitLabCredential.oauth(
            accessToken: "oauth-access-secret",
            refreshToken: "oauth-refresh-secret",
            expiresAt: expiresAt
        )
        let session = try makeSession(
            oauthApplicationID: "self-managed-application-id",
            credential: credential
        )

        #expect(session.credentialKind == .oauth)
        #expect(session.oauthApplicationID == "self-managed-application-id")
        #expect(session.oauthExpiresAt == expiresAt)
        #expect(session.canRefreshOAuth)
    }

    @Test("Models personal access token metadata")
    func modelsPersonalAccessTokenSession() throws {
        let credential = try GitLabCredential.personalAccessToken("pat-secret")
        let session = try makeSession(
            oauthApplicationID: nil,
            credential: credential
        )

        #expect(session.credentialKind == .personalAccessToken)
        #expect(session.oauthApplicationID == nil)
        #expect(session.oauthExpiresAt == nil)
        #expect(!session.canRefreshOAuth)
    }

    @Test("Round trips a stored session")
    func roundTripsStoredSession() throws {
        let original = try makeSession(
            oauthApplicationID: "application-id",
            credential: GitLabCredential.oauth(
                accessToken: "oauth-access-secret",
                refreshToken: "oauth-refresh-secret",
                expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(GitLabStoredSession.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("Redacts access and refresh tokens from descriptions")
    func redactsCredentialDescriptions() throws {
        let accessToken = "never-print-access-token"
        let refreshToken = "never-print-refresh-token"
        let credential = try GitLabCredential.oauth(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let session = try makeSession(
            oauthApplicationID: "application-id",
            credential: credential
        )

        for description in [
            String(describing: credential),
            String(reflecting: credential),
            String(describing: session),
            String(reflecting: session),
        ] {
            #expect(!description.contains(accessToken))
            #expect(!description.contains(refreshToken))
        }
    }

    @Test("Rejects contradictory credential metadata")
    func validatesCredentialMetadata() throws {
        let oauth = try GitLabCredential.oauth(
            accessToken: "oauth-secret",
            refreshToken: "refresh-secret",
            expiresAt: nil
        )
        let personalAccessToken = try GitLabCredential.personalAccessToken("pat-secret")

        #expect(throws: GitLabStoredSessionError.missingOAuthApplicationID) {
            try makeSession(oauthApplicationID: nil, credential: oauth)
        }
        #expect(throws: GitLabStoredSessionError.unexpectedOAuthApplicationID) {
            try makeSession(
                oauthApplicationID: "not-used-for-a-pat",
                credential: personalAccessToken
            )
        }
        #expect(throws: GitLabCredentialError.emptyAccessToken) {
            try GitLabCredential.personalAccessToken(" ")
        }
        #expect(throws: GitLabCredentialError.emptyRefreshToken) {
            try GitLabCredential.oauth(
                accessToken: "oauth-secret",
                refreshToken: "",
                expiresAt: nil
            )
        }
    }

    @Test("Rejects corrupt persisted session data")
    func rejectsCorruptData() {
        let emptyToken = Data(
            """
            {
              "host": "https://gitlab.example.com",
              "user": {
                "id": 42,
                "username": "octocat",
                "name": "The Octocat",
                "avatarURL": null
              },
              "oauthApplicationID": "application-id",
              "credential": {
                "kind": "oauth",
                "accessToken": "",
                "refreshToken": "refresh-secret",
                "expiresAt": "2027-01-15T08:00:00Z"
              }
            }
            """.utf8
        )
        let insecureHost = Data(
            """
            {
              "host": "http://gitlab.example.com",
              "user": {
                "id": 42,
                "username": "octocat",
                "name": "The Octocat",
                "avatarURL": null
              },
              "credential": {
                "kind": "personalAccessToken",
                "accessToken": "pat-secret"
              }
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        #expect(throws: DecodingError.self) {
            try decoder.decode(GitLabStoredSession.self, from: emptyToken)
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(GitLabStoredSession.self, from: insecureHost)
        }
    }
}

private extension GitLabStoredSessionTests {
    nonisolated func makeSession(
        oauthApplicationID: String?,
        credential: GitLabCredential
    ) throws -> GitLabStoredSession {
        try GitLabStoredSession(
            host: GitLabHost("https://gitlab.example.com/company"),
            user: GitLabUserSummary(
                id: 42,
                username: "octocat",
                name: "The Octocat",
                avatarURL: URL(string: "https://gitlab.example.com/uploads/avatar.png")
            ),
            oauthApplicationID: oauthApplicationID,
            credential: credential
        )
    }
}
