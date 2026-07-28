import Foundation

nonisolated enum GitLabMutationDeliveryCertainty:
    Equatable,
    Sendable
{
    case rejected
    case deliveryUnknown
}

extension GitLabSessionClientError {
    nonisolated var mutationDeliveryCertainty:
        GitLabMutationDeliveryCertainty
    {
        switch self {
        case .insufficientAccess,
             .refresh:
            .rejected
        case let .api(error):
            switch error {
            case .invalidRequest,
                 .unauthenticated,
                 .forbidden,
                 .notFound,
                 .validation:
                .rejected
            case .rateLimited,
                 .server,
                 .http,
                 .connectivity,
                 .cancelled,
                 .invalidResponse,
                 .decoding,
                 .transport:
                .deliveryUnknown
            }
        }
    }
}
