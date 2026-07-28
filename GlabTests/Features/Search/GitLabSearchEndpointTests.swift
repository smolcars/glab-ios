import Foundation
import Testing
@testable import Glab

@Suite("GitLab search endpoints")
struct GitLabSearchEndpointTests {
    @Test(
        "Builds one basic read request for each search scope",
        arguments: [
            GitLabSearchScope.projects,
            GitLabSearchScope.issues,
            GitLabSearchScope.mergeRequests,
        ]
    )
    func buildsBasicSearchRequest(
        scope: GitLabSearchScope
    ) throws {
        let endpoint = endpoint(
            for: scope,
            query: "review & test"
        )
        let request = try GitLabRequestBuilder(
            host: GitLabHost(
                "https://gitlab.example.com/company"
            ),
            authorization:
                .personalAccessToken("pat-secret")
        ).build(endpoint)

        #expect(endpoint.method == .get)
        #expect(endpoint.requiredAccess == .read)
        #expect(endpoint.pathComponents == ["search"])
        #expect(
            endpoint.queryItems
                == [
                    URLQueryItem(
                        name: "scope",
                        value: scope.apiValue
                    ),
                    URLQueryItem(
                        name: "search",
                        value: "review & test"
                    ),
                    URLQueryItem(
                        name: "search_type",
                        value: "basic"
                    ),
                    URLQueryItem(
                        name: "per_page",
                        value: "20"
                    ),
                ]
        )
        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/company/api/v4/search"
                    + "?scope=\(scope.apiValue)"
                    + "&search=review%20%26%20test"
                    + "&search_type=basic&per_page=20"
        )
    }
}

private extension GitLabSearchEndpointTests {
    nonisolated func endpoint(
        for scope: GitLabSearchScope,
        query: String
    ) -> GitLabAPIRequest<[GitLabSearchResult]> {
        GitLabSearchEndpoints.search(
            scope: scope,
            query: query
        )
    }
}
