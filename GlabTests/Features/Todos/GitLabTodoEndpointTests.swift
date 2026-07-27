import Foundation
import Testing
@testable import Glab

@Suite("GitLab Todo endpoints")
struct GitLabTodoEndpointTests {
    @Test(
        "Builds state and target queries",
        arguments: [
            (
                GitLabTodoState.pending,
                GitLabTodoTargetFilter.all,
                "state=pending&per_page=20"
            ),
            (
                GitLabTodoState.done,
                GitLabTodoTargetFilter.issues,
                "state=done&type=Issue&per_page=20"
            ),
            (
                GitLabTodoState.pending,
                GitLabTodoTargetFilter.mergeRequests,
                "state=pending&type=MergeRequest&per_page=20"
            ),
        ]
    )
    func buildsListQuery(
        state: GitLabTodoState,
        targetFilter: GitLabTodoTargetFilter,
        query: String
    ) throws {
        let url = try requestURL(
            GitLabTodoEndpoints.todos(
                state: state,
                targetFilter: targetFilter
            )
        )

        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/todos?\(query)"
        )
    }
}

private extension GitLabTodoEndpointTests {
    nonisolated func requestURL<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URL {
        #expect(endpoint.requiredAccess == .read)
        let request = try GitLabRequestBuilder(
            host: GitLabHost("gitlab.example.com"),
            authorization: .personalAccessToken("pat-secret")
        ).build(endpoint)

        return try #require(request.url)
    }
}
