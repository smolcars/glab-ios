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
final class ASWebAuthenticationSessionGitLabOAuthAuthenticator:
    NSObject,
    GitLabOAuthWebAuthenticating,
    ASWebAuthenticationPresentationContextProviding
{
    private var session: ASWebAuthenticationSession?

    func authenticate(
        at authorizationURL: URL,
        callbackURLScheme: String
    ) async throws(GitLabOAuthWebAuthenticationError) -> URL {
        guard session == nil else {
            throw .couldNotStart
        }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: authorizationURL,
                    callbackURLScheme: callbackURLScheme
                ) { [weak self] callbackURL, error in
                    Task { @MainActor in
                        self?.session = nil

                        if let callbackURL {
                            continuation.resume(returning: callbackURL)
                        } else if Self.isCancellation(error) {
                            continuation.resume(
                                throwing: GitLabOAuthWebAuthenticationError.cancelled
                            )
                        } else {
                            continuation.resume(
                                throwing: GitLabOAuthWebAuthenticationError.failed
                            )
                        }
                    }
                }

                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.session = session

                guard session.start() else {
                    self.session = nil
                    continuation.resume(
                        throwing: GitLabOAuthWebAuthenticationError.couldNotStart
                    )
                    return
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
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
        else {
            preconditionFailure("OAuth requires an active window scene.")
        }

        return windowScene.windows.first(where: \.isKeyWindow)
            ?? ASPresentationAnchor(windowScene: windowScene)
    }

    private static func isCancellation(_ error: (any Error)?) -> Bool {
        guard let error = error as? ASWebAuthenticationSessionError else {
            return false
        }
        return error.code == .canceledLogin
    }
}
