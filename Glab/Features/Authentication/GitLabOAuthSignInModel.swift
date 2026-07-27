import Foundation
import Observation

nonisolated enum GitLabOAuthSignInFailure:
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case configuration(GitLabOAuthConfigurationError)
    case authentication(GitLabOAuthSignInError)
    case storage(GitLabCredentialStoreError)

    var description: String {
        switch self {
        case let .configuration(error):
            error.description
        case let .authentication(error):
            error.description
        case let .storage(error):
            error.description
        }
    }
}

@MainActor
@Observable
final class GitLabOAuthSignInModel {
    static let gitLabDotComURL = "https://gitlab.com"

    var usesCustomInstance = false {
        didSet {
            clearFailureWhenChanged(from: oldValue, to: usesCustomInstance)
        }
    }
    var customInstanceURL = "" {
        didSet {
            clearFailureWhenChanged(from: oldValue, to: customInstanceURL)
            restoreApplicationIDWhenHostChanges()
        }
    }
    var customApplicationID = "" {
        didSet {
            clearFailureWhenChanged(
                from: oldValue,
                to: customApplicationID
            )
        }
    }

    private(set) var isSubmitting = false
    private(set) var failure: GitLabOAuthSignInFailure?

    var instanceURL: String {
        usesCustomInstance ? customInstanceURL : Self.gitLabDotComURL
    }

    var canSubmit: Bool {
        guard !isSubmitting else {
            return false
        }

        if usesCustomInstance {
            return !customInstanceURL.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
                && !customApplicationID.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
        }

        return gitLabDotComApplicationID != nil
    }

    var isGitLabDotComConfigured: Bool {
        gitLabDotComApplicationID != nil
    }

    var applicationSetupURL: URL? {
        guard
            let host = try? GitLabHost(instanceURL),
            var components = URLComponents(
                url: host.siteURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return nil
        }

        components.percentEncodedPath += "/-/user_settings/applications"
        return components.url
    }

    let redirectURI = GitLabOAuthConfiguration.redirectURIString

    private let authenticator: any GitLabOAuthAuthenticating
    private let appSession: AppSession
    private let applicationIDStore: any GitLabOAuthApplicationIDStoring
    private let gitLabDotComApplicationID: String?
    private var customHost: GitLabHost?

    init(
        authenticator: any GitLabOAuthAuthenticating,
        appSession: AppSession,
        applicationIDStore: any GitLabOAuthApplicationIDStoring,
        gitLabDotComApplicationID: String?
    ) {
        self.authenticator = authenticator
        self.appSession = appSession
        self.applicationIDStore = applicationIDStore
        self.gitLabDotComApplicationID = gitLabDotComApplicationID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
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

        let configuration: GitLabOAuthConfiguration

        do {
            configuration = try GitLabOAuthConfiguration(
                instanceURL: instanceURL,
                applicationID: selectedApplicationID
            )
        } catch {
            failure = .configuration(error)
            return
        }

        let session: GitLabStoredSession

        do {
            session = try await authenticator.authenticate(
                configuration: configuration
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

        if usesCustomInstance {
            applicationIDStore.save(
                configuration.applicationID,
                for: configuration.host
            )
        }
    }

    private var selectedApplicationID: String {
        usesCustomInstance
            ? customApplicationID
            : gitLabDotComApplicationID ?? ""
    }

    private func restoreApplicationIDWhenHostChanges() {
        let host = try? GitLabHost(customInstanceURL)
        guard host != customHost else {
            return
        }

        customHost = host
        customApplicationID = host.flatMap {
            applicationIDStore.applicationID(for: $0)
        } ?? ""
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

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
