import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab Todo loader")
struct LiveGitLabTodoLoaderTests {
    @Test("Loads selected queries and follows a next-page URL")
    func loadsTodoPages() async throws {
        let todo = makeTestTodo()
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "todos?page=2"
            )
        )
        let client = RecordingTodoClient(
            todo: todo,
            returnedNextPageURL: nextPageURL,
            totalCount: 38
        )
        let loader = LiveGitLabTodoLoader(client: client)

        let pending = try await loader.loadTodosPage(
            state: .pending,
            targetFilter: .all,
            after: nil
        )
        let doneIssues = try await loader.loadTodosPage(
            state: .done,
            targetFilter: .issues,
            after: nil
        )
        let nextPage = try await loader.loadTodosPage(
            state: .pending,
            targetFilter: .all,
            after: nextPageURL
        )

        #expect(pending.todos == [todo])
        #expect(pending.nextPageURL == nextPageURL)
        #expect(pending.totalCount == 38)
        #expect(doneIssues.todos == [todo])
        #expect(nextPage.todos == [todo])
        #expect(
            await client.pageSources
                == [
                    "initial:pending:all",
                    "initial:done:Issue",
                    "next:\(nextPageURL.absoluteString)",
                ]
        )
    }

    @Test("Marks one Todo and all pending Todos done")
    func completesTodos() async throws {
        let completed = makeTestTodo(
            id: 42,
            state: .done
        )
        let client = RecordingTodoClient(
            todo: completed,
            returnedNextPageURL: nil,
            totalCount: nil
        )
        let service = LiveGitLabTodoLoader(
            client: client
        )

        let response = try await service.markDone(
            id: 42
        )
        try await service.markAllDone()

        #expect(response == completed)
        #expect(
            await client.mutationPaths
                == [
                    ["todos", "42", "mark_as_done"],
                    ["todos", "mark_as_done"],
                ]
        )
        #expect(
            await client.mutationAccess
                == [.write, .write]
        )
    }
}

private extension LiveGitLabTodoLoaderTests {
    actor RecordingTodoClient:
        GitLabPaginatedSessionRequestSending
    {
        let todo: GitLabTodo
        let returnedNextPageURL: URL?
        let totalCount: Int?
        private(set) var pageSources: [String] = []
        private(set) var mutationPaths: [[String]] = []
        private(set) var mutationAccess: [
            GitLabAPIRequestAccess
        ] = []

        init(
            todo: GitLabTodo,
            returnedNextPageURL: URL?,
            totalCount: Int?
        ) {
            self.todo = todo
            self.returnedNextPageURL = returnedNextPageURL
            self.totalCount = totalCount
        }

        func send<Response>(
            _ endpoint: GitLabAPIRequest<Response>
        ) async throws(GitLabSessionClientError) -> Response {
            mutationPaths.append(
                endpoint.pathComponents
            )
            mutationAccess.append(
                endpoint.requiredAccess
            )

            if Response.self == GitLabTodo.self {
                return todo as! Response
            }
            if Response.self == GitLabEmptyResponse.self {
                return GitLabEmptyResponse() as! Response
            }
            throw .api(.invalidResponse)
        }

        func sendPage<Response>(
            _ page: GitLabAPIPageRequest<Response>
        ) async throws(GitLabSessionClientError)
            -> GitLabAPIResponse<Response>
        {
            switch page {
            case let .initial(endpoint):
                let state = endpoint.queryItems.first {
                    $0.name == "state"
                }?.value ?? "missing"
                let type = endpoint.queryItems.first {
                    $0.name == "type"
                }?.value ?? "all"
                pageSources.append(
                    "initial:\(state):\(type)"
                )
            case let .next(url):
                pageSources.append(
                    "next:\(url.absoluteString)"
                )
            }

            return GitLabAPIResponse(
                value: [todo] as! Response,
                metadata: GitLabResponseMetadata(
                    nextPageURL: returnedNextPageURL,
                    totalCount: totalCount
                )
            )
        }
    }
}
