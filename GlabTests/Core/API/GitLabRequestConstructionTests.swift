import Foundation
import Testing
@testable import Glab

@Suite("GitLab request construction")
struct GitLabRequestConstructionTests {
    @Test(
        "Normalizes GitLab hosts",
        arguments: [
            ("gitlab.example.com", "https://gitlab.example.com", "https://gitlab.example.com/api/v4"),
            ("https://gitlab.example.com/", "https://gitlab.example.com", "https://gitlab.example.com/api/v4"),
            (
                "https://gitlab.example.com:8443/company/gitlab/",
                "https://gitlab.example.com:8443/company/gitlab",
                "https://gitlab.example.com:8443/company/gitlab/api/v4"
            ),
            (
                "https://gitlab.example.com/company/gitlab/api/v4",
                "https://gitlab.example.com/company/gitlab",
                "https://gitlab.example.com/company/gitlab/api/v4"
            ),
            (
                "https://gitlab.example.com//company///gitlab/api/v4///",
                "https://gitlab.example.com/company/gitlab",
                "https://gitlab.example.com/company/gitlab/api/v4"
            ),
        ]
    )
    func normalizesGitLabHosts(input: String, siteURL: String, apiBaseURL: String) throws {
        let host = try GitLabHost(input)

        #expect(host.siteURL.absoluteString == siteURL)
        #expect(host.apiBaseURL.absoluteString == apiBaseURL)
    }

    @Test("Rejects insecure and malformed GitLab hosts")
    func rejectsInvalidHosts() {
        #expect(throws: GitLabHostError.unsupportedScheme("http")) {
            try GitLabHost("http://gitlab.example.com")
        }
        #expect(throws: GitLabHostError.credentialsNotAllowed) {
            try GitLabHost("https://user:password@gitlab.example.com")
        }
        #expect(throws: GitLabHostError.queryOrFragmentNotAllowed) {
            try GitLabHost("https://gitlab.example.com?redirect=elsewhere")
        }
        #expect(throws: GitLabHostError.missingHost) {
            try GitLabHost("https:///gitlab")
        }
    }

    @Test("Encodes path components and query values")
    func encodesPathAndQuery() throws {
        let host = try GitLabHost("https://gitlab.example.com/company")
        let endpoint = GitLabAPIRequest<TestResponse>.get(
            requires: .read,
            path: ["projects", "group/project", "merge requests"],
            query: [
                URLQueryItem(name: "search", value: "review & test"),
                URLQueryItem(name: "labels[]", value: "needs triage"),
            ]
        )

        let request = try GitLabRequestBuilder(
            host: host,
            authorization: .oauth(accessToken: "oauth-secret")
        ).build(endpoint)

        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/company/api/v4/projects/group%2Fproject/merge%20requests"
                + "?search=review%20%26%20test&labels%5B%5D=needs%20triage"
        )
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.httpBody == nil)
    }

    @Test("Builds JSON POST requests with ISO-8601 dates")
    func buildsJSONPostRequest() throws {
        let endpoint = try GitLabAPIRequest<TestResponse>.post(
            requires: .write,
            path: ["projects"],
            body: TestBody(title: "Glab", createdAt: Date(timeIntervalSince1970: 0))
        )

        let request = try GitLabRequestBuilder(
            host: GitLabHost("gitlab.com"),
            authorization: .personalAccessToken("pat-secret")
        ).build(endpoint)
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(json["title"] == "Glab")
        #expect(json["createdAt"] == "1970-01-01T00:00:00Z")
    }

    @Test("Builds POST requests without a body")
    func buildsEmptyPostRequest() throws {
        let endpoint = GitLabAPIRequest<TestResponse>.post(
            requires: .write,
            path: ["todos", "42", "mark_as_done"]
        )
        let request = try GitLabRequestBuilder(
            host: GitLabHost("gitlab.com"),
            authorization: .personalAccessToken("pat-secret")
        ).build(endpoint)

        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test("Builds DELETE requests without a body")
    func buildsDeleteRequest() throws {
        let endpoint = GitLabAPIRequest<GitLabEmptyResponse>.delete(
            requires: .write,
            path: [
                "projects",
                "42",
                "issues",
                "7",
                "award_emoji",
                "91",
            ]
        )
        let request = try GitLabRequestBuilder(
            host: GitLabHost("gitlab.com"),
            authorization: .personalAccessToken("pat-secret")
        ).build(endpoint)

        #expect(request.httpMethod == "DELETE")
        #expect(request.httpBody == nil)
        #expect(
            request.value(
                forHTTPHeaderField: "Content-Type"
            ) == nil
        )
        #expect(endpoint.requiredAccess == .write)
    }

    @Test("Carries an explicit access requirement")
    func carriesAccessRequirement() {
        let read = GitLabAPIRequest<TestResponse>.get(
            requires: .read,
            path: ["todos"]
        )
        let write = GitLabAPIRequest<TestResponse>.post(
            requires: .write,
            path: ["todos", "42", "mark_as_done"]
        )

        #expect(read.requiredAccess == .read)
        #expect(write.requiredAccess == .write)
    }

    @Test("Follows an exact trusted GitLab pagination link")
    func buildsPaginationRequest() throws {
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com:8443/company/api/v4/issues"
                    + "?scope=assigned_to_me&page=2"
            )
        )
        let request = try GitLabRequestBuilder(
            host: GitLabHost(
                "https://gitlab.example.com:8443/company"
            ),
            authorization: .personalAccessToken("pat-secret")
        ).build(
            GitLabAPIPageRequest<[TestResponse]>.next(nextPageURL)
        )

        #expect(request.url == nextPageURL)
        #expect(request.httpMethod == "GET")
        #expect(
            request.value(forHTTPHeaderField: "PRIVATE-TOKEN")
                == "pat-secret"
        )
    }

    @Test(
        "Rejects untrusted GitLab pagination links",
        arguments: [
            "http://gitlab.example.com/company/api/v4/issues?page=2",
            "https://attacker.example.com/company/api/v4/issues?page=2",
            "https://gitlab.example.com/other/api/v4/issues?page=2",
            "https://user@gitlab.example.com/company/api/v4/issues?page=2",
            "https://gitlab.example.com/company/api/v4/issues?page=2#fragment",
            "https://gitlab.example.com/company/api/v4/%2E%2E/user",
        ]
    )
    func rejectsUntrustedPaginationLinks(value: String) throws {
        let builder = try GitLabRequestBuilder(
            host: GitLabHost("https://gitlab.example.com/company"),
            authorization: .oauth(accessToken: "oauth-secret")
        )
        let url = try #require(URL(string: value))

        #expect(
            throws:
                GitLabRequestConstructionError.untrustedPaginationURL
        ) {
            try builder.build(
                GitLabAPIPageRequest<[TestResponse]>.next(url)
            )
        }
    }

    @Test("Applies OAuth and personal access token headers")
    func appliesAuthenticationHeaders() throws {
        let host = try GitLabHost("gitlab.com")
        let endpoint = GitLabAPIRequest<TestResponse>.get(
            requires: .read,
            path: ["user"]
        )
        let oauthRequest = try GitLabRequestBuilder(
            host: host,
            authorization: .oauth(accessToken: "oauth-secret")
        ).build(endpoint)
        let tokenRequest = try GitLabRequestBuilder(
            host: host,
            authorization: .personalAccessToken("pat-secret")
        ).build(endpoint)

        #expect(oauthRequest.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-secret")
        #expect(oauthRequest.value(forHTTPHeaderField: "PRIVATE-TOKEN") == nil)
        #expect(tokenRequest.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "pat-secret")
        #expect(tokenRequest.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Redacts authentication from descriptions")
    func redactsAuthenticationDescriptions() throws {
        let secret = "never-print-this-token"
        let authorization = GitLabAuthorization.oauth(accessToken: secret)
        let builder = try GitLabRequestBuilder(
            host: GitLabHost("gitlab.com"),
            authorization: authorization
        )

        #expect(!String(describing: authorization).contains(secret))
        #expect(!String(reflecting: authorization).contains(secret))
        #expect(!String(describing: builder).contains(secret))
        #expect(!String(reflecting: builder).contains(secret))
    }
}

private extension GitLabRequestConstructionTests {
    nonisolated struct TestBody: Encodable, Sendable {
        let title: String
        let createdAt: Date
    }

    nonisolated struct TestResponse: Decodable, Sendable {}
}
