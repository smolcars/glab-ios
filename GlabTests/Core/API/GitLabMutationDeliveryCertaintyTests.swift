import Foundation
import Testing
@testable import Glab

@Suite("GitLab mutation delivery certainty")
struct GitLabMutationDeliveryCertaintyTests {
    @Test(
        "Classifies locally and authoritatively rejected mutations",
        arguments: [
            GitLabSessionClientError
                .insufficientAccess(required: .write),
            .refresh(.unavailable),
            .api(.invalidRequest(.invalidURL)),
            .api(.unauthenticated),
            .api(.forbidden),
            .api(.notFound),
            .api(.validation(statusCode: 422)),
        ]
    )
    func classifiesRejected(
        _ error: GitLabSessionClientError
    ) {
        #expect(
            error.mutationDeliveryCertainty
                == .rejected
        )
    }

    @Test(
        "Classifies mutations whose delivery cannot be proven",
        arguments: [
            GitLabSessionClientError
                .api(.rateLimited(retryAfterSeconds: nil)),
            .api(.server(statusCode: 503)),
            .api(.http(statusCode: 409)),
            .api(.connectivity(.networkConnectionLost)),
            .api(.cancelled),
            .api(.invalidResponse),
            .api(.decoding),
            .api(.transport),
        ]
    )
    func classifiesDeliveryUnknown(
        _ error: GitLabSessionClientError
    ) {
        #expect(
            error.mutationDeliveryCertainty
                == .deliveryUnknown
        )
    }
}
