import Foundation

nonisolated enum GitLabAPIError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case invalidRequest(GitLabRequestConstructionError)
    case unauthenticated
    case forbidden
    case notFound
    case validation(statusCode: Int)
    case rateLimited(retryAfterSeconds: Int?)
    case server(statusCode: Int)
    case http(statusCode: Int)
    case connectivity(URLError.Code)
    case cancelled
    case invalidResponse
    case decoding
    case transport

    var description: String {
        switch self {
        case let .invalidRequest(error):
            error.description
        case .unauthenticated:
            "Your GitLab session is no longer valid. Sign in again."
        case .forbidden:
            "Your GitLab account does not have permission to do that."
        case .notFound:
            "GitLab could not find that resource, or you cannot access it."
        case let .validation(statusCode):
            "GitLab rejected the request (HTTP \(statusCode))."
        case let .rateLimited(retryAfterSeconds):
            if let retryAfterSeconds {
                "GitLab is receiving too many requests. Try again in \(retryAfterSeconds) seconds."
            } else {
                "GitLab is receiving too many requests. Try again later."
            }
        case let .server(statusCode):
            "GitLab is temporarily unavailable (HTTP \(statusCode))."
        case let .http(statusCode):
            "GitLab returned an unexpected response (HTTP \(statusCode))."
        case let .connectivity(code):
            Self.connectivityDescription(for: code)
        case .cancelled:
            "The GitLab request was cancelled."
        case .invalidResponse:
            "GitLab returned an invalid network response."
        case .decoding:
            "GitLab returned data that this version of Glab could not read."
        case .transport:
            "The GitLab request could not be completed."
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }

    static func httpStatus(
        _ statusCode: Int,
        retryAfterSeconds: Int? = nil
    ) -> Self {
        switch statusCode {
        case 400, 409, 422:
            .validation(
                statusCode: statusCode
            )
        case 401:
            .unauthenticated
        case 403:
            .forbidden
        case 404:
            .notFound
        case 429:
            .rateLimited(
                retryAfterSeconds:
                    retryAfterSeconds
            )
        case 500...599:
            .server(
                statusCode: statusCode
            )
        default:
            .http(
                statusCode: statusCode
            )
        }
    }

    private static func connectivityDescription(for code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet:
            "Connect to the internet and try again."
        case .timedOut:
            "The GitLab request timed out."
        case .cannotFindHost:
            "The GitLab host could not be found."
        case .cannotConnectToHost:
            "Glab could not connect to the GitLab host."
        case .networkConnectionLost:
            "The network connection was lost."
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            "Glab could not establish a secure connection to GitLab."
        default:
            "A network error prevented the GitLab request."
        }
    }
}
