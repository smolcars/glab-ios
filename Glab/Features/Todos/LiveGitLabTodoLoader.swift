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

    func loadTodosFirstPage(
        state: GitLabTodoState,
        targetFilter: GitLabTodoTargetFilter,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<GitLabTodo>
            ) async -> Void
    ) async throws(GitLabSessionClientError)
}

extension GitLabTodoLoading {
    func loadTodosFirstPage(
        state: GitLabTodoState,
        targetFilter: GitLabTodoTargetFilter,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<GitLabTodo>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let page = try await loadTodosPage(
            state: state,
            targetFilter: targetFilter,
            after: nil
        )
        await onPage(
            GitLabResourcePageEvent(
                page: GitLabResourcePage(
                    items: page.todos,
                    nextPageURL: page.nextPageURL,
                    totalCount: page.totalCount
                ),
                source: .network
            )
        )
    }
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
    private let pageSize: Int

    init(
        client: any GitLabPaginatedSessionRequestSending,
        pageSize: Int = 20
    ) {
        self.client = client
        self.pageSize = pageSize
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
                        targetFilter: targetFilter,
                        perPage: pageSize
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
    func loadTodosFirstPage(
        state: GitLabTodoState,
        targetFilter: GitLabTodoTargetFilter,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<GitLabTodo>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadPage(
            .initial(
                GitLabTodoEndpoints.todos(
                    state: state,
                    targetFilter: targetFilter,
                    perPage: pageSize
                )
            ),
            cachePolicy: .todos,
            refreshBehavior: refreshBehavior
        ) {
            await onPage(
                GitLabResourcePageEvent(
                    apiResponse: $0
                )
            )
        }
    }

    @concurrent
    func markDone(
        id: Int
    ) async throws(GitLabSessionClientError) -> GitLabTodo {
        let todo = try await client.send(
            GitLabTodoEndpoints.markDone(id: id)
        )
        await invalidateTodoCaches()
        return todo
    }

    @concurrent
    func markAllDone()
        async throws(GitLabSessionClientError)
    {
        let _: GitLabEmptyResponse = try await client.send(
            GitLabTodoEndpoints.markAllDone()
        )
        await invalidateTodoCaches()
    }

    private func invalidateTodoCaches() async {
        for state in GitLabTodoState.allCases {
            for targetFilter
                in GitLabTodoTargetFilter.allCases
            {
                await client.invalidateCachedResponse(
                    GitLabTodoEndpoints.todos(
                        state: state,
                        targetFilter: targetFilter,
                        perPage: pageSize
                    )
                )
            }
        }
    }
}
