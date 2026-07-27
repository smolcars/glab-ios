import Foundation
import Observation

nonisolated enum PersonalAccessTokenSignInFailure:
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case authentication(PersonalAccessTokenSignInError)
    case storage(GitLabCredentialStoreError)

    var description: String {
        switch self {
        case let .authentication(error):
            error.description
        case let .storage(error):
            error.description
        }
    }
}

@MainActor
@Observable
final class PersonalAccessTokenSignInModel {
    static let gitLabDotComURL = "https://gitlab.com"

    var usesCustomInstance = false {
        didSet {
            clearFailureWhenChanged(from: oldValue, to: usesCustomInstance)
        }
    }
    var customInstanceURL = "" {
        didSet {
            clearFailureWhenChanged(from: oldValue, to: customInstanceURL)
        }
    }
    var token = "" {
        didSet {
            clearFailureWhenChanged(from: oldValue, to: token)
        }
    }

    private(set) var isSubmitting = false
    private(set) var failure: PersonalAccessTokenSignInFailure?

    var canSubmit: Bool {
        guard !isSubmitting else {
            return false
        }

        let hasToken = !token.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        let hasInstance = !usesCustomInstance
            || !customInstanceURL.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty

        return hasToken && hasInstance
    }

    var instanceURL: String {
        usesCustomInstance ? customInstanceURL : Self.gitLabDotComURL
    }

    var personalAccessTokenSetupURL: URL? {
        guard
            let host = try? GitLabHost(instanceURL),
            var components = URLComponents(
                url: host.siteURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return nil
        }

        components.percentEncodedPath += "/-/user_settings/personal_access_tokens"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Glab"),
            URLQueryItem(name: "description", value: "Glab for iOS"),
            URLQueryItem(name: "scopes", value: "api"),
        ]
        return components.url
    }

    private let authenticator: any PersonalAccessTokenAuthenticating
    private let appSession: AppSession

    init(
        authenticator: any PersonalAccessTokenAuthenticating,
        appSession: AppSession
    ) {
        self.authenticator = authenticator
        self.appSession = appSession
    }

    func signIn() async {
        guard !isSubmitting else {
            return
        }

        failure = nil
        isSubmitting = true
        defer {
            isSubmitting = false
        }

        let session: GitLabStoredSession

        do {
            session = try await authenticator.authenticate(
                instanceURL: instanceURL,
                token: token
            )
        } catch {
            guard !Task.isCancelled else {
                return
            }
            failure = .authentication(error)
            return
        }

        guard !Task.isCancelled else {
            return
        }

        do {
            try await appSession.establish(session)
        } catch {
            failure = .storage(error)
            return
        }

        token = ""
    }

    private func clearFailureWhenChanged<Value: Equatable>(
        from oldValue: Value,
        to newValue: Value
    ) {
        if oldValue != newValue {
            failure = nil
        }
    }
}
