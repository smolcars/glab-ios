import Foundation
import Testing
@testable import Glab

@Suite("GitLab recovery presentation")
struct GitLabRecoveryPresentationTests {
    @Test(
        "Presents API failures consistently",
        arguments: [
            (
                GitLabSessionClientError.api(
                    .connectivity(.notConnectedToInternet)
                ),
                "You’re offline",
                "wifi.slash",
                GitLabRecoveryPresentation.RetryAvailability.available
            ),
            (
                GitLabSessionClientError.api(
                    .connectivity(.timedOut)
                ),
                "GitLab took too long",
                "clock.badge.exclamationmark",
                .available
            ),
            (
                GitLabSessionClientError.api(
                    .connectivity(.cannotConnectToHost)
                ),
                "Can’t reach GitLab",
                "network.slash",
                .available
            ),
            (
                GitLabSessionClientError.api(
                    .server(statusCode: 503)
                ),
                "GitLab is unavailable",
                "exclamationmark.icloud",
                .available
            ),
            (
                GitLabSessionClientError.api(.forbidden),
                "Access denied",
                "lock.fill",
                .unavailable
            ),
            (
                GitLabSessionClientError.api(.unauthenticated),
                "Sign in again",
                "person.crop.circle.badge.exclamationmark",
                .unavailable
            ),
            (
                GitLabSessionClientError.api(
                    .rateLimited(retryAfterSeconds: 30)
                ),
                "Too many requests",
                "hourglass",
                .after(seconds: 30)
            ),
            (
                GitLabSessionClientError.api(
                    .rateLimited(retryAfterSeconds: nil)
                ),
                "Too many requests",
                "hourglass",
                .available
            ),
            (
                GitLabSessionClientError.api(.decoding),
                "Couldn’t read GitLab’s response",
                "doc.badge.exclamationmark",
                .unavailable
            ),
            (
                GitLabSessionClientError.api(.notFound),
                "GitLab item unavailable",
                "magnifyingglass",
                .unavailable
            ),
        ]
    )
    func presentsAPIFailure(
        error: GitLabSessionClientError,
        title: String,
        systemImage: String,
        retryAvailability:
            GitLabRecoveryPresentation.RetryAvailability
    ) {
        let presentation = GitLabRecoveryPresentation(error: error)

        #expect(presentation.title == title)
        #expect(presentation.systemImage == systemImage)
        #expect(
            presentation.retryAvailability
                == retryAvailability
        )
        #expect(presentation.message == error.description)
    }

    @Test("Treats read-only access as a permission failure")
    func presentsInsufficientAccess() {
        let error = GitLabSessionClientError.insufficientAccess(
            required: .write
        )
        let presentation = GitLabRecoveryPresentation(error: error)

        #expect(presentation.title == "Access denied")
        #expect(presentation.systemImage == "lock.fill")
        #expect(
            presentation.retryAvailability
                == .unavailable
        )
        #expect(presentation.message == error.description)
    }

    @Test(
        "Presents session refresh failures with the correct recovery",
        arguments: [
            (
                GitLabSessionClientError.refresh(
                    .token(.invalidGrant)
                ),
                "Sign in again",
                GitLabRecoveryPresentation.RetryAvailability.unavailable
            ),
            (
                GitLabSessionClientError.refresh(
                    .token(.connectivity(.timedOut))
                ),
                "GitLab took too long",
                .available
            ),
            (
                GitLabSessionClientError.refresh(
                    .token(.server(statusCode: 503))
                ),
                "GitLab is unavailable",
                .available
            ),
            (
                GitLabSessionClientError.refresh(
                    .storage(.keychain(status: -50))
                ),
                "Couldn’t refresh your session",
                .unavailable
            ),
        ]
    )
    func presentsRefreshFailure(
        error: GitLabSessionClientError,
        title: String,
        retryAvailability:
            GitLabRecoveryPresentation.RetryAvailability
    ) {
        let presentation = GitLabRecoveryPresentation(error: error)

        #expect(presentation.title == title)
        #expect(
            presentation.retryAvailability
                == retryAvailability
        )
        #expect(presentation.message == error.description)
    }

    @Test("Generic recovery copy remains retryable")
    func createsGenericPresentation() {
        let presentation = GitLabRecoveryPresentation.generic(
            message: "Several GitLab sections could not be loaded."
        )

        #expect(presentation.title == "Couldn’t load GitLab")
        #expect(
            presentation.retryAvailability
                == .available
        )
    }
}
