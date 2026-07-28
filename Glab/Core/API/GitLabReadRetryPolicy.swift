import Foundation

nonisolated struct GitLabReadRetryPolicy: Sendable {
    static let standard = Self(
        delays: [
            .milliseconds(500),
            .seconds(1),
        ]
    )

    private let delays: [Duration]

    private init(delays: [Duration]) {
        self.delays = delays
    }

    func delay(
        after error: GitLabAPIError,
        retryNumber: Int
    ) -> Duration? {
        guard
            retryNumber > 0,
            retryNumber <= delays.count,
            isRetryable(error)
        else {
            return nil
        }

        return delays[retryNumber - 1]
    }

    private func isRetryable(
        _ error: GitLabAPIError
    ) -> Bool {
        switch error {
        case .server,
             .transport:
            true
        case let .connectivity(code):
            switch code {
            case .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed:
                true
            default:
                false
            }
        default:
            false
        }
    }
}
