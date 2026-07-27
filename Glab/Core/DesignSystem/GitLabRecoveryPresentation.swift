import Foundation

nonisolated struct GitLabRecoveryPresentation:
    Equatable,
    Hashable,
    Sendable
{
    enum RetryAvailability:
        Equatable,
        Hashable,
        Sendable
    {
        case available
        case after(seconds: Int)
        case unavailable
    }

    let title: String
    let message: String
    let systemImage: String
    let retryAvailability: RetryAvailability

    init(error: GitLabSessionClientError) {
        if error.requiresReauthentication {
            self = Self(
                title: "Sign in again",
                message: error.description,
                systemImage:
                    "person.crop.circle.badge.exclamationmark",
                retryAvailability: .unavailable
            )
            return
        }

        switch error {
        case let .api(apiError):
            self = Self.presentation(
                for: apiError,
                message: error.description
            )
        case let .refresh(refreshError):
            self = Self.presentation(
                for: refreshError,
                message: error.description
            )
        case .insufficientAccess:
            self = Self(
                title: "Access denied",
                message: error.description,
                systemImage: "lock.fill",
                retryAvailability: .unavailable
            )
        }
    }

    static func generic(
        message: String
    ) -> Self {
        Self(
            title: "Couldn’t load GitLab",
            message: message,
            systemImage: "exclamationmark.triangle",
            retryAvailability: .available
        )
    }

    private init(
        title: String,
        message: String,
        systemImage: String,
        retryAvailability: RetryAvailability
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.retryAvailability = retryAvailability
    }

    private static func presentation(
        for error: GitLabAPIError,
        message: String
    ) -> Self {
        switch error {
        case let .connectivity(code):
            connectivityPresentation(
                for: code,
                message: message
            )
        case .server:
            serverPresentation(message: message)
        case .forbidden:
            Self(
                title: "Access denied",
                message: message,
                systemImage: "lock.fill",
                retryAvailability: .unavailable
            )
        case .unauthenticated:
            Self(
                title: "Sign in again",
                message: message,
                systemImage:
                    "person.crop.circle.badge.exclamationmark",
                retryAvailability: .unavailable
            )
        case let .rateLimited(retryAfterSeconds):
            Self(
                title: "Too many requests",
                message: message,
                systemImage: "hourglass",
                retryAvailability:
                    retryAfterSeconds.map {
                        .after(seconds: $0)
                    } ?? .available
            )
        case .decoding,
             .invalidResponse:
            Self(
                title: "Couldn’t read GitLab’s response",
                message: message,
                systemImage: "doc.badge.exclamationmark",
                retryAvailability: .unavailable
            )
        case .notFound:
            Self(
                title: "GitLab item unavailable",
                message: message,
                systemImage: "magnifyingglass",
                retryAvailability: .unavailable
            )
        case .transport:
            unreachablePresentation(message: message)
        case .http:
            Self(
                title: "GitLab returned an unexpected response",
                message: message,
                systemImage: "exclamationmark.triangle",
                retryAvailability: .available
            )
        case .invalidRequest,
             .validation,
             .cancelled:
            Self(
                title: "Couldn’t complete the request",
                message: message,
                systemImage: "exclamationmark.triangle",
                retryAvailability: .unavailable
            )
        }
    }

    private static func presentation(
        for error: GitLabOAuthRefreshError,
        message: String
    ) -> Self {
        switch error {
        case let .token(.connectivity(code)):
            connectivityPresentation(
                for: code,
                message: message
            )
        case .token(.server):
            serverPresentation(message: message)
        case .token(.transport):
            unreachablePresentation(message: message)
        case .token(.http):
            Self(
                title: "GitLab returned an unexpected response",
                message: message,
                systemImage: "exclamationmark.triangle",
                retryAvailability: .available
            )
        default:
            Self(
                title: "Couldn’t refresh your session",
                message: message,
                systemImage:
                    "person.crop.circle.badge.exclamationmark",
                retryAvailability: .unavailable
            )
        }
    }

    private static func connectivityPresentation(
        for code: URLError.Code,
        message: String
    ) -> Self {
        switch code {
        case .notConnectedToInternet:
            Self(
                title: "You’re offline",
                message: message,
                systemImage: "wifi.slash",
                retryAvailability: .available
            )
        case .timedOut:
            Self(
                title: "GitLab took too long",
                message: message,
                systemImage:
                    "clock.badge.exclamationmark",
                retryAvailability: .available
            )
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            Self(
                title: "Secure connection failed",
                message: message,
                systemImage: "lock.trianglebadge.exclamationmark",
                retryAvailability: .unavailable
            )
        default:
            unreachablePresentation(message: message)
        }
    }

    private static func serverPresentation(
        message: String
    ) -> Self {
        Self(
            title: "GitLab is unavailable",
            message: message,
            systemImage: "exclamationmark.icloud",
            retryAvailability: .available
        )
    }

    private static func unreachablePresentation(
        message: String
    ) -> Self {
        Self(
            title: "Can’t reach GitLab",
            message: message,
            systemImage: "network.slash",
            retryAvailability: .available
        )
    }
}
