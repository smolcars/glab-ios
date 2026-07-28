import Foundation
import Testing
@testable import Glab

@Suite("Personal access token sign-in model")
@MainActor
struct PersonalAccessTokenSignInModelTests {
    @Test("Uses GitLab.com by default and persists a validated session")
    func signsInToGitLabDotCom() async throws {
        let session = try makeSession(
            host: "gitlab.com",
            token: "validated-secret"
        )
        let authenticator = StubAuthenticator(outcome: .success(session))
        let store = InMemoryGitLabCredentialStore()
        let appSession = AppSession(credentialStore: store)
        let model = PersonalAccessTokenSignInModel(
            authenticator: authenticator,
            appSession: appSession
        )
        model.token = "validated-secret"

        #expect(model.instanceURL == "https://gitlab.com")
        #expect(model.canSubmit)

        await model.signIn()

        #expect(appSession.state == .signedIn(session))
        #expect(
            try await store.load(
                for: GitLabAccountID(session: session)
            ) == session
        )
        #expect(model.token.isEmpty)
        #expect(model.failure == nil)
        #expect(!model.isSubmitting)
        #expect(
            await authenticator.recordedInputs()
                == [.init(instanceURL: "https://gitlab.com", token: "validated-secret")]
        )
    }

    @Test("Uses the entered self-managed instance")
    func signsInToCustomInstance() async throws {
        let session = try makeSession(
            host: "gitlab.example.com/company",
            token: "validated-secret"
        )
        let authenticator = StubAuthenticator(outcome: .success(session))
        let model = PersonalAccessTokenSignInModel(
            authenticator: authenticator,
            appSession: AppSession(
                credentialStore: InMemoryGitLabCredentialStore()
            )
        )
        model.usesCustomInstance = true
        model.customInstanceURL = "gitlab.example.com/company"
        model.token = "validated-secret"

        await model.signIn()

        #expect(
            await authenticator.recordedInputs()
                == [
                    .init(
                        instanceURL: "gitlab.example.com/company",
                        token: "validated-secret"
                    ),
                ]
        )
    }

    @Test("Failed validation never persists the token")
    func doesNotPersistInvalidCredentials() async throws {
        let authenticator = StubAuthenticator(
            outcome: .failure(.invalidToken)
        )
        let store = InMemoryGitLabCredentialStore()
        let appSession = AppSession(credentialStore: store)
        await appSession.restore()
        let model = PersonalAccessTokenSignInModel(
            authenticator: authenticator,
            appSession: appSession
        )
        model.token = "rejected-secret"

        await model.signIn()

        #expect(appSession.state == .signedOut)
        #expect(
            try await store.load(
                for: GitLabAccountID(
                    host: GitLabHost("gitlab.com"),
                    userID: 42
                )
            ) == nil
        )
        #expect(model.token == "rejected-secret")
        #expect(model.failure == .authentication(.invalidToken))
        #expect(
            !String(describing: model.failure)
                .contains("rejected-secret")
        )
        #expect(
            !String(reflecting: model.failure)
                .contains("rejected-secret")
        )
        #expect(!model.isSubmitting)
    }

    @Test("Surfaces secure storage failures and keeps input for retry")
    func handlesStorageFailure() async throws {
        let session = try makeSession(
            host: "gitlab.com",
            token: "validated-secret"
        )
        let storeError = GitLabCredentialStoreError.keychain(status: -1)
        let model = PersonalAccessTokenSignInModel(
            authenticator: StubAuthenticator(outcome: .success(session)),
            appSession: AppSession(
                credentialStore: SaveFailingCredentialStore(error: storeError)
            )
        )
        model.token = "validated-secret"

        await model.signIn()

        #expect(model.token == "validated-secret")
        #expect(model.failure == .storage(storeError))
        #expect(!model.isSubmitting)
    }

    @Test("Requires a token and a selected custom instance")
    func computesSubmissionAvailability() {
        let model = PersonalAccessTokenSignInModel(
            authenticator: StubAuthenticator(outcome: .failure(.invalidToken)),
            appSession: AppSession(
                credentialStore: InMemoryGitLabCredentialStore()
            )
        )

        #expect(!model.canSubmit)

        model.token = "pat-secret"
        #expect(model.canSubmit)

        model.usesCustomInstance = true
        #expect(!model.canSubmit)

        model.customInstanceURL = "gitlab.example.com"
        #expect(model.canSubmit)
    }

    @Test("Builds token setup links for the selected instance")
    func buildsTokenSetupLinks() {
        let model = PersonalAccessTokenSignInModel(
            authenticator: StubAuthenticator(outcome: .failure(.invalidToken)),
            appSession: AppSession(
                credentialStore: InMemoryGitLabCredentialStore()
            )
        )

        #expect(
            model.personalAccessTokenSetupURL?.absoluteString
                == "https://gitlab.com/-/user_settings/personal_access_tokens"
                + "?name=Glab&description=Glab%20for%20iOS&scopes=api"
        )

        model.usesCustomInstance = true
        model.customInstanceURL = "gitlab.example.com/company/api/v4/"

        #expect(
            model.personalAccessTokenSetupURL?.absoluteString
                == "https://gitlab.example.com/company/-/user_settings/personal_access_tokens"
                + "?name=Glab&description=Glab%20for%20iOS&scopes=api"
        )

        model.customInstanceURL = "http://insecure.example.com"

        #expect(model.personalAccessTokenSetupURL == nil)
    }

    @Test("Editing input clears the previous failure")
    func clearsFailureWhenEditing() async {
        let model = PersonalAccessTokenSignInModel(
            authenticator: StubAuthenticator(outcome: .failure(.invalidToken)),
            appSession: AppSession(
                credentialStore: InMemoryGitLabCredentialStore()
            )
        )
        model.token = "rejected-secret"
        await model.signIn()
        #expect(model.failure == .authentication(.invalidToken))

        model.token = "replacement-secret"

        #expect(model.failure == nil)
    }

    @Test("Ignores a second submission while authentication is running")
    func preventsDuplicateSubmission() async throws {
        let authenticator = ControlledAuthenticator(
            session: try makeSession(
                host: "gitlab.com",
                token: "validated-secret"
            )
        )
        let model = PersonalAccessTokenSignInModel(
            authenticator: authenticator,
            appSession: AppSession(
                credentialStore: InMemoryGitLabCredentialStore()
            )
        )
        model.token = "validated-secret"

        let firstSubmission = Task {
            await model.signIn()
        }
        await authenticator.waitUntilStarted()

        #expect(model.isSubmitting)
        #expect(!model.canSubmit)

        await model.signIn()

        #expect(await authenticator.callCount == 1)

        await authenticator.finish()
        await firstSubmission.value

        #expect(!model.isSubmitting)
    }

    @Test("Cancelled submission never persists a late success")
    func cancelledSubmissionDoesNotEstablishSession() async throws {
        let session = try makeSession(
            host: "gitlab.com",
            token: "validated-secret"
        )
        let authenticator = ControlledAuthenticator(session: session)
        let store = InMemoryGitLabCredentialStore()
        let appSession = AppSession(credentialStore: store)
        await appSession.restore()
        let model = PersonalAccessTokenSignInModel(
            authenticator: authenticator,
            appSession: appSession
        )
        model.token = "validated-secret"

        let submission = Task {
            await model.signIn()
        }
        await authenticator.waitUntilStarted()

        submission.cancel()
        await authenticator.finish()
        await submission.value

        #expect(appSession.state == .signedOut)
        #expect(
            try await store.load(
                for: GitLabAccountID(session: session)
            ) == nil
        )
        #expect(model.token == "validated-secret")
        #expect(model.failure == nil)
        #expect(!model.isSubmitting)
    }
}

private extension PersonalAccessTokenSignInModelTests {
    nonisolated struct SignInInput: Equatable, Sendable {
        let instanceURL: String
        let token: String
    }

    nonisolated enum StubOutcome: Sendable {
        case success(GitLabStoredSession)
        case failure(PersonalAccessTokenSignInError)
    }

    actor StubAuthenticator: PersonalAccessTokenAuthenticating {
        private let outcome: StubOutcome
        private var inputs: [SignInInput] = []

        init(outcome: StubOutcome) {
            self.outcome = outcome
        }

        func authenticate(
            instanceURL: String,
            token: String
        ) async throws(PersonalAccessTokenSignInError) -> GitLabStoredSession {
            inputs.append(.init(instanceURL: instanceURL, token: token))

            switch outcome {
            case let .success(session):
                return session
            case let .failure(error):
                throw error
            }
        }

        func recordedInputs() -> [SignInInput] {
            inputs
        }
    }

    actor ControlledAuthenticator: PersonalAccessTokenAuthenticating {
        private let session: GitLabStoredSession
        private var startedContinuation: CheckedContinuation<Void, Never>?
        private var finishContinuation: CheckedContinuation<Void, Never>?
        private(set) var callCount = 0

        init(session: GitLabStoredSession) {
            self.session = session
        }

        func authenticate(
            instanceURL: String,
            token: String
        ) async throws(PersonalAccessTokenSignInError) -> GitLabStoredSession {
            callCount += 1
            startedContinuation?.resume()
            startedContinuation = nil

            await withCheckedContinuation { continuation in
                finishContinuation = continuation
            }

            return session
        }

        func waitUntilStarted() async {
            guard callCount == 0 else {
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

    nonisolated struct SaveFailingCredentialStore: GitLabCredentialStore {
        let error: GitLabCredentialStoreError

        func load(
            for accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) -> GitLabStoredSession? {
            nil
        }

        func save(
            _ session: GitLabStoredSession
        ) async throws(GitLabCredentialStoreError) {
            throw error
        }

        func delete(
            _ accountID: GitLabAccountID
        ) async throws(GitLabCredentialStoreError) {}
    }

    nonisolated func makeSession(
        host: String,
        token: String
    ) throws -> GitLabStoredSession {
        try GitLabStoredSession(
            host: GitLabHost(host),
            user: GitLabUserSummary(
                id: 42,
                username: "octocat",
                name: "The Octocat",
                avatarURL: nil
            ),
            oauthApplicationID: nil,
            personalAccessTokenMetadata: GitLabPersonalAccessTokenMetadata(
                scopes: ["api"],
                expiresOn: "2027-07-27"
            ),
            credential: GitLabCredential.personalAccessToken(token)
        )
    }
}
