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
            ),
            access: .read
        )

        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/todos?\(query)"
        )
    }

    @Test("Builds the single Todo completion request")
    func buildsMarkDoneRequest() throws {
        let endpoint: GitLabAPIRequest<GitLabTodo> =
            GitLabTodoEndpoints.markDone(id: 42)
        let url = try requestURL(
            endpoint,
            access: .write
        )

        #expect(endpoint.method == .post)
        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "todos/42/mark_as_done"
        )
    }

    @Test("Builds the mark-all completion request")
    func buildsMarkAllDoneRequest() throws {
        let endpoint:
            GitLabAPIRequest<GitLabEmptyResponse> =
                GitLabTodoEndpoints.markAllDone()
        let url = try requestURL(
            endpoint,
            access: .write
        )

        #expect(endpoint.method == .post)
        #expect(
            url.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "todos/mark_as_done"
        )
    }
}

private extension GitLabTodoEndpointTests {
    nonisolated func requestURL<Response>(
        _ endpoint: GitLabAPIRequest<Response>,
        access: GitLabAPIRequestAccess
    ) throws -> URL {
        #expect(endpoint.requiredAccess == access)
        let request = try GitLabRequestBuilder(
            host: GitLabHost("gitlab.example.com"),
            authorization: .personalAccessToken("pat-secret")
        ).build(endpoint)

        return try #require(request.url)
    }
}
