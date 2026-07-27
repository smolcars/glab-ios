import Foundation

nonisolated enum GitLabAuthorization: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case oauth(accessToken: String)
    case personalAccessToken(String)

    var description: String {
        switch self {
        case .oauth:
            "OAuth access token (<redacted>)"
        case .personalAccessToken:
            "Personal access token (<redacted>)"
        }
    }

    var debugDescription: String {
        description
    }

    func apply(to request: inout URLRequest) {
        switch self {
        case let .oauth(accessToken):
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        case let .personalAccessToken(token):
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        }
    }
}
