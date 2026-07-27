import AuthenticationServices
import Foundation
import Testing
@testable import Glab

@Suite("GitLab OAuth web authentication")
@MainActor
struct GitLabOAuthWebAuthenticationTests {
    @Test("Cancels the browser session and permits a later attempt")
    func cancelsAndResetsActiveSession() async throws {
        let firstSession = StubWebAuthenticationSession()
        let secondSession = StubWebAuthenticationSession()
        var sessions = [firstSession, secondSession]
        let authenticator = makeAuthenticator { completion in
            let session = sessions.removeFirst()
            session.completion = completion
            return session
        }

        let firstAttempt = Task {
            try await authenticator.authenticate(
                at: try #require(
                    URL(string: "https://gitlab.example.com/oauth/authorize")
                ),
                callbackURLScheme: "glab"
            )
        }
        await firstSession.waitUntilStarted()
        firstAttempt.cancel()

        await #expect(
            throws: GitLabOAuthWebAuthenticationError.cancelled
        ) {
            try await firstAttempt.value
        }
        #expect(firstSession.cancelCount == 1)

        firstSession.complete(
            callbackURL: URL(string: "glab://oauth/callback?code=late")
        )

        let secondAttempt = Task {
            try await authenticator.authenticate(
                at: try #require(
                    URL(string: "https://gitlab.example.com/oauth/authorize")
                ),
                callbackURLScheme: "glab"
            )
        }
        await secondSession.waitUntilStarted()
        let expectedCallback = try #require(
            URL(string: "glab://oauth/callback?code=current")
        )
        secondSession.complete(callbackURL: expectedCallback)

        #expect(try await secondAttempt.value == expectedCallback)
        #expect(secondSession.cancelCount == 0)
    }

    @Test("Does not start without a foreground presentation anchor")
    func rejectsMissingPresentationAnchor() async throws {
        var factoryCallCount = 0
        let authenticator =
            ASWebAuthenticationSessionGitLabOAuthAuthenticator(
                sessionFactory: { _, _, _ in
                    factoryCallCount += 1
                    return StubWebAuthenticationSession()
                },
                presentationAnchorProvider: { nil }
            )

        await #expect(
            throws: GitLabOAuthWebAuthenticationError.couldNotStart
        ) {
            try await authenticator.authenticate(
                at: try #require(
                    URL(string: "https://gitlab.example.com/oauth/authorize")
                ),
                callbackURLScheme: "glab"
            )
        }
        #expect(factoryCallCount == 0)
    }
}

private extension GitLabOAuthWebAuthenticationTests {
    final class StubWebAuthenticationSession:
        GitLabOAuthWebAuthenticationSession
    {
        var presentationContextProvider:
            (any ASWebAuthenticationPresentationContextProviding)?
        var prefersEphemeralWebBrowserSession = true
        var completion: ((URL?, (any Error)?) -> Void)?
        private var startedContinuations: [
            CheckedContinuation<Void, Never>
        ] = []
        private(set) var isStarted = false
        private(set) var cancelCount = 0

        func start() -> Bool {
            isStarted = true
            let continuations = startedContinuations
            startedContinuations.removeAll()
            continuations.forEach { $0.resume() }
            return true
        }

        func cancel() {
            cancelCount += 1
        }

        func waitUntilStarted() async {
            guard !isStarted else {
                return
            }

            await withCheckedContinuation {
                startedContinuations.append($0)
            }
        }

        func complete(
            callbackURL: URL?,
            error: (any Error)? = nil
        ) {
            completion?(callbackURL, error)
        }
    }

    func makeAuthenticator(
        sessionFactory:
            @escaping (
                @escaping (URL?, (any Error)?) -> Void
            ) -> StubWebAuthenticationSession
    ) -> ASWebAuthenticationSessionGitLabOAuthAuthenticator {
        ASWebAuthenticationSessionGitLabOAuthAuthenticator(
            sessionFactory: { _, _, completion in
                sessionFactory(completion)
            },
            presentationAnchorProvider: {
                ASPresentationAnchor()
            }
        )
    }
}
