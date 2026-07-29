import Foundation

nonisolated enum GitLabRawFileSessionError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case session(GitLabSessionClientError)
    case responseTooLarge
    case incompleteResponse
    case unsafeRedirect
    case storageFailure

    var description: String {
        switch self {
        case let .session(error):
            error.description
        case .responseTooLarge:
            "This GitLab file is too large to open safely."
        case .incompleteResponse:
            "GitLab stopped sending the file before it was complete."
        case .unsafeRedirect:
            "GitLab redirected the file to an unsafe destination."
        case .storageFailure:
            "The GitLab file could not be stored securely."
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }

    var requiresReauthentication: Bool {
        switch self {
        case let .session(error):
            error.requiresReauthentication
        default:
            false
        }
    }
}

nonisolated protocol GitLabRawFileSessionDownloading:
    Sendable
{
    func downloadRawFile(
        _ endpoint: GitLabRawAPIRequest,
        maximumByteCount: Int,
        temporaryDirectory: URL
    ) async throws(GitLabRawFileSessionError)
        -> GitLabHTTPDownloadedFile
}
