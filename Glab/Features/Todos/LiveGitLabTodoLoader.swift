import Foundation

nonisolated struct GitLabTodoPage:
    Equatable,
    Sendable
{
    let todos: [GitLabTodo]
    let nextPageURL: URL?
    let totalCount: Int?
}

nonisolated protocol GitLabTodoLoading: Sendable {
    func loadTodosPage(
        state: GitLabTodoState,
        targetFilter: GitLabTodoTargetFilter,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabTodoPage
}

nonisolated protocol GitLabTodoMutating: Sendable {
    func markDone(
        id: Int
    ) async throws(GitLabSessionClientError) -> GitLabTodo

    func markAllDone()
        async throws(GitLabSessionClientError)
}

nonisolated struct LiveGitLabTodoLoader:
    GitLabTodoLoading,
    GitLabTodoMutating,
    Sendable
{
    private let client:
        any GitLabPaginatedSessionRequestSending

    init(
        client: any GitLabPaginatedSessionRequestSending
    ) {
        self.client = client
    }

    @concurrent
    func loadTodosPage(
        state: GitLabTodoState,
        targetFilter: GitLabTodoTargetFilter,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabTodoPage
    {
        let request: GitLabAPIPageRequest<[GitLabTodo]> =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(
                    GitLabTodoEndpoints.todos(
                        state: state,
                        targetFilter: targetFilter
                    )
                )
            }
        let response = try await client.sendPage(request)

        return GitLabTodoPage(
            todos: response.value,
            nextPageURL: response.metadata.nextPageURL,
            totalCount: response.metadata.totalCount
        )
    }

    @concurrent
    func markDone(
        id: Int
    ) async throws(GitLabSessionClientError) -> GitLabTodo {
        try await client.send(
            GitLabTodoEndpoints.markDone(id: id)
        )
    }

    @concurrent
    func markAllDone()
        async throws(GitLabSessionClientError)
    {
        let _: GitLabEmptyResponse = try await client.send(
            GitLabTodoEndpoints.markAllDone()
        )
    }
}
