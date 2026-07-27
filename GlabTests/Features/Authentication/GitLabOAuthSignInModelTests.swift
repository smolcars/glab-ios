import Foundation
import Testing
@testable import Glab

@Suite("GitLab OAuth sign-in model")
@MainActor
struct GitLabOAuthSignInModelTests {
    @Test("Uses the configured GitLab.com Application ID and persists the session")
    func signsInToGitLabDotCom() async throws {
        let session = try makeOAuthSession(host: "gitlab.com")
        let authenticator = StubAuthenticator(outcome: .success(session))
        let store = InMemoryGitLabCredentialStore()
        let appSession = AppSession(credentialStore: store)
        let model = makeModel(
            authenticator: authenticator,
            appSession: appSession,
            gitLabDotComApplicationID: "gitlab-com-application-id"
        )

        #expect(model.canSubmit)
        #expect(model.isGitLabDotComConfigured)

        await model.signIn()

        #expect(appSession.state == .signedIn(session))
        #expect(try await store.load() == session)
        #expect(
            authenticator.configurations
                == [
                    try GitLabOAuthConfiguration(
                        instanceURL: "https://gitlab.com",
                        applicationID: "gitlab-com-application-id"
                    ),
                ]
        )
        #expect(model.failure == nil)
    }

    @Test("Restores and saves a self-managed Application ID by normalized host")
    func persistsSelfManagedConfiguration() async throws {
        let applicationIDStore = StubApplicationIDStore()
        let host = try GitLabHost("gitlab.example.com/company")
        applicationIDStore.save("saved-application-id", for: host)
        let session = try makeOAuthSession(
            host: "gitlab.example.com/company"
        )
        let model = makeModel(
            authenticator: StubAuthenticator(outcome: .success(session)),
            applicationIDStore: applicationIDStore
        )
        model.usesCustomInstance = true
        model.customInstanceURL =
            "https://gitlab.example.com//company/api/v4/"

        #expect(model.customApplicationID == "saved-application-id")
        #expect(model.canSubmit)

        model.customApplicationID = "replacement-application-id"
        await model.signIn()

        #expect(
            applicationIDStore.applicationID(for: host)
                == "replacement-application-id"
        )
    }

    @Test("Does not save self-managed configuration after authentication failure")
    func doesNotPersistFailedConfiguration() async {
        let applicationIDStore = StubApplicationIDStore()
        let model = makeModel(
            authenticator: StubAuthenticator(
                outcome: .failure(.token(.invalidApplication))
            ),
            applicationIDStore: applicationIDStore
        )
        model.usesCustomInstance = true
        model.customInstanceURL = "gitlab.example.com"
        model.customApplicationID = "rejected-application-id"

        await model.signIn()

        #expect(
            model.failure
                == .authentication(.token(.invalidApplication))
        )
        #expect(applicationIDStore.applicationIDs.isEmpty)
    }

    @Test("Requires configuration and surfaces invalid self-managed hosts")
    func validatesConfiguration() async {
        let model = makeModel(
            authenticator: StubAuthenticator(
                outcome: .failure(.unsupportedResponse)
            ),
            gitLabDotComApplicationID: nil
        )

        #expect(!model.isGitLabDotComConfigured)
        #expect(!model.canSubmit)

        model.usesCustomInstance = true
        model.customInstanceURL = "http://insecure.example.com"
        model.customApplicationID = "application-id"

        #expect(model.canSubmit)
        await model.signIn()

        #expect(
            model.failure
                == .configuration(
                    .invalidHost(.unsupportedScheme("http"))
                )
        )
    }

    @Test("Does not save self-managed configuration when Keychain persistence fails")
    func doesNotPersistAfterStorageFailure() async throws {
        let applicationIDStore = StubApplicationIDStore()
        let storeError = GitLabCredentialStoreError.keychain(status: -1)
        let model = makeModel(
            authenticator: StubAuthenticator(
                outcome: .success(
                    try makeOAuthSession(host: "gitlab.example.com")
                )
            ),
            appSession: AppSession(
                credentialStore: SaveFailingCredentialStore(
                    error: storeError
                )
            ),
            applicationIDStore: applicationIDStore
        )
        model.usesCustomInstance = true
        model.customInstanceURL = "gitlab.example.com"
        model.customApplicationID = "application-id"

        await model.signIn()

        #expect(model.failure == .storage(storeError))
        #expect(applicationIDStore.applicationIDs.isEmpty)
    }

    @Test("Cancelled submission never persists a late success")
    func cancelledSubmissionDoesNotEstablishSession() async throws {
        let authenticator = ControlledAuthenticator(
            session: try makeOAuthSession(host: "gitlab.example.com")
        )
        let store = InMemoryGitLabCredentialStore()
        let appSession = AppSession(credentialStore: store)
        await appSession.restore()
        let applicationIDStore = StubApplicationIDStore()
        let model = GitLabOAuthSignInModel(
            authenticator: authenticator,
            appSession: appSession,
            applicationIDStore: applicationIDStore,
            gitLabDotComApplicationID: nil
        )
        model.usesCustomInstance = true
        model.customInstanceURL = "gitlab.example.com"
        model.customApplicationID = "application-id"

        let submission = Task {
            await model.signIn()
        }
        await authenticator.waitUntilStarted()

        submission.cancel()
        authenticator.finish()
        await submission.value

        #expect(appSession.state == .signedOut)
        #expect(try await store.load() == nil)
        #expect(applicationIDStore.applicationIDs.isEmpty)
        #expect(model.failure == nil)
        #expect(!model.isSubmitting)
    }

    @Test("Builds the OAuth application setup link for the selected host")
    func buildsApplicationSetupURL() {
        let model = makeModel(
            authenticator: StubAuthenticator(
                outcome: .failure(.unsupportedResponse)
            ),
            gitLabDotComApplicationID: "application-id"
        )

        #expect(
            model.applicationSetupURL?.absoluteString
                == "https://gitlab.com/-/user_settings/applications"
        )

        model.usesCustomInstance = true
        model.customInstanceURL = "gitlab.example.com/company/api/v4/"

        #expect(
            model.applicationSetupURL?.absoluteString
                == "https://gitlab.example.com/company"
                + "/-/user_settings/applications"
        )
    }

    @Test("Reads runtime configuration from environment before Info.plist")
    func readsRuntimeConfiguration() {
        #expect(
            GitLabOAuthRuntimeConfiguration.gitLabDotComApplicationID(
                environment: [
                    GitLabOAuthRuntimeConfiguration.environmentKey:
                        " environment-id ",
                ],
                informationPropertyList: [
                    GitLabOAuthRuntimeConfiguration
                        .informationPropertyListKey: "plist-id",
                ]
            ) == "environment-id"
        )
        #expect(
            GitLabOAuthRuntimeConfiguration.gitLabDotComApplicationID(
                environment: [:],
                informationPropertyList: [
                    GitLabOAuthRuntimeConfiguration
                        .informationPropertyListKey: " plist-id ",
                ]
            ) == "plist-id"
        )
    }

    @Test("Stores non-secret Application IDs by normalized host")
    func storesApplicationIDsInUserDefaults() throws {
        let suiteName = "GitLabOAuthSignInModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = UserDefaultsGitLabOAuthApplicationIDStore(
            defaults: defaults
        )
        let host = try GitLabHost("gitlab.example.com/company")

        store.save(" application-id ", for: host)

        #expect(store.applicationID(for: host) == "application-id")
        #expect(
            store.applicationID(
                for: try GitLabHost(
                    "https://gitlab.example.com//company/api/v4/"
                )
            ) == "application-id"
        )
        #expect(
            store.applicationID(
                for: try GitLabHost("gitlab.example.com/other")
            ) == nil
        )
    }
}

private extension GitLabOAuthSignInModelTests {
    @MainActor
    final class StubAuthenticator: GitLabOAuthAuthenticating {
        enum Outcome {
            case success(GitLabStoredSession)
            case failure(GitLabOAuthSignInError)
        }

        let outcome: Outcome
        private(set) var configurations: [GitLabOAuthConfiguration] = []

        init(outcome: Outcome) {
            self.outcome = outcome
        }

        func authenticate(
            configuration: GitLabOAuthConfiguration
        ) async throws(GitLabOAuthSignInError) -> GitLabStoredSession {
            configurations.append(configuration)

            switch outcome {
            case let .success(session):
                return session
            case let .failure(error):
                throw error
            }
        }
    }

    @MainActor
    final class ControlledAuthenticator: GitLabOAuthAuthenticating {
        private let session: GitLabStoredSession
        private var startedContinuation:
            CheckedContinuation<Void, Never>?
        private var finishContinuation:
            CheckedContinuation<Void, Never>?
        private var hasStarted = false

        init(session: GitLabStoredSession) {
            self.session = session
        }

        func authenticate(
            configuration: GitLabOAuthConfiguration
        ) async throws(GitLabOAuthSignInError) -> GitLabStoredSession {
            hasStarted = true
            startedContinuation?.resume()
            startedContinuation = nil

            await withCheckedContinuation { continuation in
                finishContinuation = continuation
            }

            return session
        }

        func waitUntilStarted() async {
            guard !hasStarted else {
                return
            }

            await withCheckedContinuation { continuation in
                startedContinuation = continuation
            }
        }

        func finish() {
            finishContinuation?.resume()
            finishContinuation = nil
        }
    }

    @MainActor
    final class StubApplicationIDStore:
        GitLabOAuthApplicationIDStoring
    {
        private(set) var applicationIDs: [String: String] = [:]

        func applicationID(for host: GitLabHost) -> String? {
            applicationIDs[host.siteURL.absoluteString]
        }

        func save(_ applicationID: String, for host: GitLabHost) {
            applicationIDs[host.siteURL.absoluteString] = applicationID
        }
    }

    nonisolated struct SaveFailingCredentialStore: GitLabCredentialStore {
        let error: GitLabCredentialStoreError

        func load() async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
            nil
        }

        func save(
            _ session: GitLabStoredSession
        ) async throws(GitLabCredentialStoreError) {
            throw error
        }

        func delete() async throws(GitLabCredentialStoreError) {}
    }

    func makeModel(
        authenticator: StubAuthenticator,
        appSession: AppSession? = nil,
        applicationIDStore: StubApplicationIDStore = StubApplicationIDStore(),
        gitLabDotComApplicationID: String? = "gitlab-com-application-id"
    ) -> GitLabOAuthSignInModel {
        GitLabOAuthSignInModel(
            authenticator: authenticator,
            appSession: appSession ?? AppSession(
                credentialStore: InMemoryGitLabCredentialStore()
            ),
            applicationIDStore: applicationIDStore,
            gitLabDotComApplicationID: gitLabDotComApplicationID
        )
    }

    nonisolated func makeOAuthSession(
        host: String
    ) throws -> GitLabStoredSession {
        try GitLabStoredSession(
            host: GitLabHost(host),
            user: GitLabUserSummary(
                id: 42,
                username: "octocat",
                name: "The Octocat",
                avatarURL: nil
            ),
            oauthApplicationID: "application-id",
            personalAccessTokenMetadata: nil,
            credential: GitLabCredential.oauth(
                accessToken: "oauth-access",
                refreshToken: "oauth-refresh",
                expiresAt: .distantFuture
            )
        )
    }
}
