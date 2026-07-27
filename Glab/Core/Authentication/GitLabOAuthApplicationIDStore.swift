import Foundation

@MainActor
protocol GitLabOAuthApplicationIDStoring: Sendable {
    func applicationID(for host: GitLabHost) -> String?
    func save(_ applicationID: String, for host: GitLabHost)
}

@MainActor
final class UserDefaultsGitLabOAuthApplicationIDStore:
    GitLabOAuthApplicationIDStoring
{
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "oauthApplicationIDsByHost"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func applicationID(for host: GitLabHost) -> String? {
        let value = storedApplicationIDs[host.siteURL.absoluteString]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    func save(_ applicationID: String, for host: GitLabHost) {
        let normalizedApplicationID = applicationID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedApplicationID.isEmpty else {
            return
        }

        var applicationIDs = storedApplicationIDs
        applicationIDs[host.siteURL.absoluteString] = normalizedApplicationID
        defaults.set(applicationIDs, forKey: storageKey)
    }

    private var storedApplicationIDs: [String: String] {
        defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }
}

@MainActor
enum GitLabOAuthRuntimeConfiguration {
    static let environmentKey = "GLAB_GITLAB_COM_OAUTH_APPLICATION_ID"
    static let informationPropertyListKey =
        "GLABGitLabComOAuthApplicationID"

    static func gitLabDotComApplicationID(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        informationPropertyList: [String: Any]? = Bundle.main.infoDictionary
    ) -> String? {
        normalizedApplicationID(environment[environmentKey])
            ?? normalizedApplicationID(
                informationPropertyList?[informationPropertyListKey] as? String
            )
    }

    private static func normalizedApplicationID(_ value: String?) -> String? {
        let normalizedValue = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalizedValue?.isEmpty == false ? normalizedValue : nil
    }
}
