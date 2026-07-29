import Foundation
import Testing
@testable import Glab

@Suite("GitLab HTTP file redirect policy")
struct GitLabHTTPFileRedirectPolicyTests {
    @Test("Preserves credentials for the original HTTPS origin")
    func preservesSameOriginCredentials() throws {
        let policy = try makePolicy()
        let proposed = authenticatedRequest(
            url:
                "https://gitlab.example.com:443"
                + "/uploads/job-trace.txt"
        )

        let decision = try policy.redirect(
            proposed,
            from: policy.initialState
        )

        #expect(decision.state.redirectCount == 1)
        #expect(
            decision.state.canForwardCredentials
        )
        expectCredentials(
            in: decision.request,
            arePresent: true
        )
    }

    @Test("Restores trusted values over proposed same-origin credentials")
    func replacesProposedSameOriginCredentials()
        throws
    {
        let policy = try makePolicy()
        var proposed = authenticatedRequest(
            url:
                "https://gitlab.example.com"
                + "/uploads/job-trace.txt"
        )
        proposed.setValue(
            "Bearer hostile-secret",
            forHTTPHeaderField:
                "Authorization"
        )

        let decision = try policy.redirect(
            proposed,
            from: policy.initialState
        )

        #expect(
            decision.request.value(
                forHTTPHeaderField:
                    "Authorization"
            ) == "Bearer oauth-secret"
        )
    }

    @Test("Strips every sensitive header across origins")
    func stripsCrossOriginCredentials() throws {
        let policy = try makePolicy()
        let proposed = authenticatedRequest(
            url:
                "https://objects.example.net"
                + "/job-trace.txt"
        )

        let decision = try policy.redirect(
            proposed,
            from: policy.initialState
        )

        #expect(
            !decision.state
                .canForwardCredentials
        )
        expectCredentials(
            in: decision.request,
            arePresent: false
        )
        #expect(
            decision.request.value(
                forHTTPHeaderField: "Accept"
            ) == "text/plain"
        )
    }

    @Test("Never restores credentials after leaving the GitLab origin")
    func neverRestoresCredentials() throws {
        let policy = try makePolicy()
        let first = try policy.redirect(
            authenticatedRequest(
                url:
                    "https://objects.example.net"
                    + "/first"
            ),
            from: policy.initialState
        )
        let proposed = authenticatedRequest(
            url:
                "https://cdn.example.net"
                + "/second"
        )

        let second = try policy.redirect(
            proposed,
            from: first.state
        )

        #expect(
            !second.state
                .canForwardCredentials
        )
        expectCredentials(
            in: second.request,
            arePresent: false
        )
    }

    @Test(
        "Rejects unsafe redirect destinations",
        arguments: [
            "http://gitlab.example.com/trace",
            "https://user@gitlab.example.com/trace",
            "https://user:password@gitlab.example.com/trace",
            "https://gitlab.example.com/trace#fragment",
            "https:///trace",
            "file:///tmp/trace",
        ]
    )
    func rejectsUnsafeDestinations(
        destination: String
    ) throws {
        let policy = try makePolicy()

        #expect(
            throws:
                GitLabHTTPFileRedirectError
                .unsafeDestination
        ) {
            _ = try policy.redirect(
                URLRequest(
                    url: try #require(
                        URL(string: destination)
                    )
                ),
                from: policy.initialState
            )
        }
    }

    @Test("Rejects a redirect without a URL")
    func rejectsMissingDestination() throws {
        let policy = try makePolicy()

        #expect(
            throws:
                GitLabHTTPFileRedirectError
                .unsafeDestination
        ) {
            _ = try policy.redirect(
                URLRequest(
                    url:
                        URL(
                            string:
                                "https://example.com"
                        )!
                )
                .withoutURL,
                from: policy.initialState
            )
        }
    }

    @Test("Permits five redirects and rejects the sixth")
    func enforcesRedirectLimit() throws {
        let policy = try makePolicy()
        var state = policy.initialState

        for index in 1...5 {
            let decision = try policy.redirect(
                URLRequest(
                    url: try #require(
                        URL(
                            string:
                                "https://objects.example.net/"
                                + "\(index)"
                        )
                    )
                ),
                from: state
            )
            state = decision.state
        }

        #expect(state.redirectCount == 5)
        #expect(
            throws:
                GitLabHTTPFileRedirectError
                .tooManyRedirects
        ) {
            _ = try policy.redirect(
                URLRequest(
                    url: try #require(
                        URL(
                            string:
                                "https://objects.example.net/6"
                        )
                    )
                ),
                from: state
            )
        }
    }

    @Test("Rejects a redirect loop before the hop limit")
    func rejectsRedirectLoop() throws {
        let policy = try makePolicy()
        let first = try policy.redirect(
            URLRequest(
                url: try #require(
                    URL(
                        string:
                            "https://objects.example.net/trace"
                    )
                )
            ),
            from: policy.initialState
        )

        #expect(
            throws:
                GitLabHTTPFileRedirectError
                .redirectLoop
        ) {
            _ = try policy.redirect(
                URLRequest(
                    url: try #require(
                        URL(
                            string:
                                "https://objects.example.net/trace"
                        )
                    )
                ),
                from: first.state
            )
        }
    }

    @Test("Treats an explicit HTTPS default port as the same origin")
    func normalizesDefaultHTTPSPort() throws {
        let initial = authenticatedRequest(
            url:
                "https://gitlab.example.com:443"
                + "/api/v4/projects/42/jobs/910/trace"
        )
        let policy =
            try GitLabHTTPFileRedirectPolicy(
                initialRequest: initial
            )

        let decision = try policy.redirect(
            authenticatedRequest(
                url:
                    "https://gitlab.example.com"
                    + "/uploads/trace"
            ),
            from: policy.initialState
        )

        #expect(
            decision.state.canForwardCredentials
        )
        expectCredentials(
            in: decision.request,
            arePresent: true
        )
    }

    @Test("Does not expose destinations through errors")
    func errorsDoNotExposeDestination() {
        let description =
            GitLabHTTPFileRedirectError
            .unsafeDestination
            .localizedDescription

        #expect(
            !description.contains(
                "gitlab.example.com"
            )
        )
        #expect(
            !description.contains("trace")
        )
    }

    @Test("Policy descriptions redact credentials")
    func descriptionsRedactCredentials()
        throws
    {
        let policy = try makePolicy()
        let descriptions = [
            String(describing: policy),
            String(reflecting: policy),
        ]

        for description in descriptions {
            #expect(
                description.contains("redacted")
            )
            #expect(
                !description.contains(
                    "oauth-secret"
                )
            )
            #expect(
                !description.contains(
                    "personal-secret"
                )
            )
            #expect(
                !description.contains(
                    "job-secret"
                )
            )
            #expect(
                !description.contains(
                    "proxy-secret"
                )
            )
        }
    }

    private func makePolicy()
        throws -> GitLabHTTPFileRedirectPolicy
    {
        try GitLabHTTPFileRedirectPolicy(
            initialRequest:
                authenticatedRequest(
                    url:
                        "https://gitlab.example.com"
                        + "/api/v4/projects/42/jobs/910/trace"
                )
        )
    }

    private func authenticatedRequest(
        url: String
    ) -> URLRequest {
        var request = URLRequest(
            url: URL(string: url)!
        )
        request.setValue(
            "Bearer oauth-secret",
            forHTTPHeaderField:
                "Authorization"
        )
        request.setValue(
            "personal-secret",
            forHTTPHeaderField:
                "PRIVATE-TOKEN"
        )
        request.setValue(
            "job-secret",
            forHTTPHeaderField:
                "JOB-TOKEN"
        )
        request.setValue(
            "administrator",
            forHTTPHeaderField: "Sudo"
        )
        request.setValue(
            "session=secret",
            forHTTPHeaderField: "Cookie"
        )
        request.setValue(
            "Basic proxy-secret",
            forHTTPHeaderField:
                "Proxy-Authorization"
        )
        request.setValue(
            "text/plain",
            forHTTPHeaderField: "Accept"
        )
        return request
    }

    private func expectCredentials(
        in request: URLRequest,
        arePresent: Bool
    ) {
        let names = [
            "Authorization",
            "PRIVATE-TOKEN",
            "JOB-TOKEN",
            "Sudo",
            "Cookie",
            "Proxy-Authorization",
        ]
        for name in names {
            #expect(
                (
                    request.value(
                        forHTTPHeaderField: name
                    ) != nil
                ) == arePresent
            )
        }
    }
}

private extension URLRequest {
    var withoutURL: Self {
        var copy = self
        copy.url = nil
        return copy
    }
}
