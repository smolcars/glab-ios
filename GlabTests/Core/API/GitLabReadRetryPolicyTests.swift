import Foundation
import Testing
@testable import Glab

@Suite("GitLab read retry policy")
struct GitLabReadRetryPolicyTests {
    @Test("Uses two bounded exponential delays")
    func computesDelays() {
        let policy = GitLabReadRetryPolicy.standard
        let error = GitLabAPIError.server(statusCode: 503)

        #expect(
            policy.delay(
                after: error,
                retryNumber: 1
            ) == .milliseconds(500)
        )
        #expect(
            policy.delay(
                after: error,
                retryNumber: 2
            ) == .seconds(1)
        )
        #expect(
            policy.delay(
                after: error,
                retryNumber: 3
            ) == nil
        )
    }

    @Test(
        "Retries only transient failures",
        arguments: [
            (GitLabAPIError.server(statusCode: 500), true),
            (GitLabAPIError.transport, true),
            (GitLabAPIError.connectivity(.timedOut), false),
            (GitLabAPIError.connectivity(.networkConnectionLost), true),
            (GitLabAPIError.connectivity(.cannotConnectToHost), true),
            (GitLabAPIError.connectivity(.cannotFindHost), true),
            (GitLabAPIError.connectivity(.dnsLookupFailed), true),
            (GitLabAPIError.connectivity(.notConnectedToInternet), false),
            (GitLabAPIError.unauthenticated, false),
            (GitLabAPIError.forbidden, false),
            (GitLabAPIError.rateLimited(retryAfterSeconds: 30), false),
            (GitLabAPIError.decoding, false),
            (GitLabAPIError.invalidResponse, false),
            (GitLabAPIError.cancelled, false),
        ]
    )
    func classifiesFailure(
        error: GitLabAPIError,
        isRetryable: Bool
    ) {
        let delay = GitLabReadRetryPolicy.standard.delay(
            after: error,
            retryNumber: 1
        )

        #expect((delay != nil) == isRetryable)
    }
}
