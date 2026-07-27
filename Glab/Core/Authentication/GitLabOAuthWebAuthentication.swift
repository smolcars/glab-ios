import AuthenticationServices
import Foundation
import UIKit

nonisolated enum GitLabOAuthWebAuthenticationError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible
{
    case cancelled
    case couldNotStart
    case failed

    var description: String {
        switch self {
        case .cancelled:
            "GitLab sign-in was cancelled."
        case .couldNotStart:
            "Glab could not open the GitLab sign-in page."
        case .failed:
            "The GitLab web sign-in could not be completed."
        }
    }

    var errorDescription: String? {
        description
    }
}

@MainActor
protocol GitLabOAuthWebAuthenticating: Sendable {
    func authenticate(
        at authorizationURL: URL,
        callbackURLScheme: String
    ) async throws(GitLabOAuthWebAuthenticationError) -> URL
}

@MainActor
protocol GitLabOAuthWebAuthenticationSession: AnyObject {
    var presentationContextProvider:
        (any ASWebAuthenticationPresentationContextProviding)? { get set }
    var prefersEphemeralWebBrowserSession: Bool { get set }

    func start() -> Bool
    func cancel()
}

extension ASWebAuthenticationSession:
    GitLabOAuthWebAuthenticationSession
{}

@MainActor
final class ASWebAuthenticationSessionGitLabOAuthAuthenticator:
    NSObject,
    GitLabOAuthWebAuthenticating,
    ASWebAuthenticationPresentationContextProviding
{
    typealias SessionFactory = @MainActor (
        URL,
        String?,
        @escaping (URL?, (any Error)?) -> Void
    ) -> any GitLabOAuthWebAuthenticationSession
    typealias PresentationAnchorProvider =
        @MainActor () -> ASPresentationAnchor?

    private let sessionFactory: SessionFactory
    private let presentationAnchorProvider: PresentationAnchorProvider
    private var session: (any GitLabOAuthWebAuthenticationSession)?
    private var continuation: CheckedContinuation<URL, any Error>?
    private var activePresentationAnchor: ASPresentationAnchor?

    override init() {
        sessionFactory = { authorizationURL, callbackURLScheme, completion in
            ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackURLScheme,
                completionHandler: completion
            )
        }
        presentationAnchorProvider = Self.foregroundPresentationAnchor
        super.init()
    }

    init(
        sessionFactory: @escaping SessionFactory,
        presentationAnchorProvider:
            @escaping PresentationAnchorProvider
    ) {
        self.sessionFactory = sessionFactory
        self.presentationAnchorProvider = presentationAnchorProvider
        super.init()
    }

    func authenticate(
        at authorizationURL: URL,
        callbackURLScheme: String
    ) async throws(GitLabOAuthWebAuthenticationError) -> URL {
        guard session == nil, continuation == nil else {
            throw .couldNotStart
        }
        guard !Task.isCancelled else {
            throw .cancelled
        }
        guard let presentationAnchor = presentationAnchorProvider() else {
            throw .couldNotStart
        }

        do {
            activePresentationAnchor = presentationAnchor

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    continuation in
                    guard !Task.isCancelled else {
                        activePresentationAnchor = nil
                        continuation.resume(
                            throwing:
                                GitLabOAuthWebAuthenticationError.cancelled
                        )
                        return
                    }

                    self.continuation = continuation
                    let session = sessionFactory(
                        authorizationURL,
                        callbackURLScheme
                    ) { [weak self] callbackURL, error in
                        Task { @MainActor in
                            self?.complete(
                                callbackURL: callbackURL,
                                error: error
                            )
                        }
                    }

                    session.presentationContextProvider = self
                    session.prefersEphemeralWebBrowserSession = false
                    self.session = session

                    guard session.start() else {
                        finish(with: .failure(.couldNotStart))
                        return
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelActiveSession()
                }
            }
        } catch let error as GitLabOAuthWebAuthenticationError {
            throw error
        } catch {
            throw .failed
        }
    }

    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        guard let activePresentationAnchor else {
            preconditionFailure(
                "An OAuth session cannot request a presentation anchor "
                    + "before it starts."
            )
        }

        return activePresentationAnchor
    }

    private static func isCancellation(_ error: (any Error)?) -> Bool {
        guard let error = error as? ASWebAuthenticationSessionError else {
            return false
        }
        return error.code == .canceledLogin
    }

    private static func foregroundPresentationAnchor() -> ASPresentationAnchor? {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: {
                    $0.activationState == .foregroundActive
                })
        else {
            return nil
        }

        return windowScene.windows.first(where: \.isKeyWindow)
            ?? ASPresentationAnchor(windowScene: windowScene)
    }

    private func complete(
        callbackURL: URL?,
        error: (any Error)?
    ) {
        if let callbackURL {
            finish(with: .success(callbackURL))
        } else if Self.isCancellation(error) {
            finish(with: .failure(.cancelled))
        } else {
            finish(with: .failure(.failed))
        }
    }

    private func cancelActiveSession() {
        guard continuation != nil else {
            return
        }

        session?.cancel()
        finish(with: .failure(.cancelled))
    }

    private func finish(
        with result: Result<
            URL,
            GitLabOAuthWebAuthenticationError
        >
    ) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        session = nil
        activePresentationAnchor = nil

        switch result {
        case let .success(callbackURL):
            continuation.resume(returning: callbackURL)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
