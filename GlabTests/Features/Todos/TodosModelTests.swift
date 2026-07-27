import Foundation
import Testing
@testable import Glab

@Suite("Todos model")
@MainActor
struct TodosModelTests {
    @Test("Appends pages without duplicate Todo IDs")
    func appendsPagesWithoutDuplicates() async throws {
        let first = makeTestTodo(id: 1, title: "First")
        let second = makeTestTodo(id: 2, title: "Second")
        let duplicateSecond = makeTestTodo(
            id: 2,
            title: "Duplicate second"
        )
        let third = makeTestTodo(id: 3, title: "Third")
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "todos?page=2"
            )
        )
        let loader = StubTodoLoader(
            pageResults: [
                .success(
                    GitLabTodoPage(
                        todos: [first, second],
                        nextPageURL: nextPageURL,
                        totalCount: 3
                    )
                ),
                .success(
                    GitLabTodoPage(
                        todos: [duplicateSecond, third],
                        nextPageURL: nil,
                        totalCount: 3
                    )
                ),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: loader,
            apiAccess: .readWrite
        )

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(
            after: try #require(model.todos.last)
        )

        #expect(
            model.todos.map(\.title)
                == ["First", "Second", "Third"]
        )
        #expect(model.nextPageURL == nil)
        #expect(model.pendingBadgeCount == 3)
        #expect(
            await loader.pageStates
                == [.pending, .pending]
        )
        #expect(
            await loader.pageTargetFilters
                == [.all, .all]
        )
        #expect(
            await loader.pageRequestURLs
                == [nil, nextPageURL]
        )
    }

    @Test("Caches each state and target selection")
    func cachesSelections() async {
        let pending = makeTestTodo(
            id: 1,
            title: "Pending",
            state: .pending
        )
        let done = makeTestTodo(
            id: 2,
            title: "Done",
            state: .done
        )
        let issue = makeTestTodo(
            id: 3,
            title: "Issue",
            targetType: .issue
        )
        let loader = StubTodoLoader(
            pageResults: [
                .success(
                    GitLabTodoPage(
                        todos: [pending],
                        nextPageURL: nil,
                        totalCount: 1
                    )
                ),
                .success(
                    GitLabTodoPage(
                        todos: [done],
                        nextPageURL: nil,
                        totalCount: 1
                    )
                ),
                .success(
                    GitLabTodoPage(
                        todos: [issue],
                        nextPageURL: nil,
                        totalCount: 1
                    )
                ),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: loader,
            apiAccess: .readWrite
        )

        await model.loadIfNeeded()
        model.selectedState = .done
        await model.loadIfNeeded()
        model.selectedState = .pending
        await model.loadIfNeeded()
        model.selectedTargetFilter = .issues
        await model.loadIfNeeded()

        #expect(model.todos == [issue])
        #expect(
            await loader.pageStates
                == [.pending, .done, .pending]
        )
        #expect(
            await loader.pageTargetFilters
                == [.all, .all, .issues]
        )
    }

    @Test("Uses a server total for a partial pending badge")
    func derivesBadgeFromServerTotal() async throws {
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "todos?page=2"
            )
        )
        let loader = StubTodoLoader(
            pageResults: [
                .success(
                    GitLabTodoPage(
                        todos: [makeTestTodo()],
                        nextPageURL: nextPageURL,
                        totalCount: 27
                    )
                ),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: loader,
            apiAccess: .readWrite
        )

        await model.loadIfNeeded()

        #expect(model.pendingBadgeCount == 27)
    }

    @Test("Uses row count only for a completed collection")
    func derivesBadgeFromCompleteCollection() async {
        let loader = StubTodoLoader(
            pageResults: [
                .success(
                    GitLabTodoPage(
                        todos: [
                            makeTestTodo(id: 1),
                            makeTestTodo(id: 2),
                        ],
                        nextPageURL: nil,
                        totalCount: nil
                    )
                ),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: loader,
            apiAccess: .readWrite
        )

        await model.loadIfNeeded()

        #expect(model.pendingBadgeCount == 2)
    }

    @Test("Does not infer a badge from a partial collection")
    func omitsBadgeForPartialCollection() async throws {
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "todos?page=2"
            )
        )
        let loader = StubTodoLoader(
            pageResults: [
                .success(
                    GitLabTodoPage(
                        todos: [makeTestTodo()],
                        nextPageURL: nextPageURL,
                        totalCount: nil
                    )
                ),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: loader,
            apiAccess: .readWrite
        )

        await model.loadIfNeeded()

        #expect(model.pendingBadgeCount == nil)
    }

    @Test("Preserves rows and hides a stale badge after refresh failure")
    func preservesRowsAfterRefreshFailure() async {
        let todo = makeTestTodo()
        let loader = StubTodoLoader(
            pageResults: [
                .success(
                    GitLabTodoPage(
                        todos: [todo],
                        nextPageURL: nil,
                        totalCount: 1
                    )
                ),
                .failure(.api(.server(statusCode: 503))),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: loader,
            apiAccess: .readWrite
        )

        await model.loadIfNeeded()
        await model.refresh()

        #expect(model.todos == [todo])
        #expect(model.didFailRefresh)
        #expect(model.pendingBadgeCount == nil)
        #expect(
            model.loadError == .api(.server(statusCode: 503))
        )
    }

    @Test("Cancelled refresh retry preserves the previous failure")
    func preservesRefreshFailureAfterCancellation() async {
        let todo = makeTestTodo()
        let serverError = GitLabSessionClientError.api(
            .server(statusCode: 503)
        )
        let loader = StubTodoLoader(
            pageResults: [
                .success(
                    GitLabTodoPage(
                        todos: [todo],
                        nextPageURL: nil,
                        totalCount: 1
                    )
                ),
                .failure(serverError),
                .failure(.api(.cancelled)),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: loader,
            apiAccess: .readWrite
        )

        await model.loadIfNeeded()
        await model.refresh()
        await model.refresh()

        #expect(model.todos == [todo])
        #expect(model.didFailRefresh)
        #expect(model.pendingBadgeCount == nil)
        #expect(model.loadError == serverError)
    }

    @Test("Retries a failed next page")
    func retriesNextPage() async throws {
        let first = makeTestTodo(id: 1)
        let second = makeTestTodo(id: 2)
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "todos?page=2"
            )
        )
        let loader = StubTodoLoader(
            pageResults: [
                .success(
                    GitLabTodoPage(
                        todos: [first],
                        nextPageURL: nextPageURL,
                        totalCount: 2
                    )
                ),
                .failure(.api(.server(statusCode: 503))),
                .success(
                    GitLabTodoPage(
                        todos: [second],
                        nextPageURL: nil,
                        totalCount: 2
                    )
                ),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: loader,
            apiAccess: .readWrite
        )

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(after: first)
        #expect(model.didFailNextPage)
        #expect(model.todos == [first])

        await model.retryNextPage()

        #expect(model.todos == [first, second])
        #expect(!model.didFailNextPage)
        #expect(model.loadError == nil)
    }

    @Test("Cancelled page retry preserves the previous failure")
    func preservesPageFailureAfterCancellation() async throws {
        let first = makeTestTodo(id: 1)
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "todos?page=2"
            )
        )
        let serverError = GitLabSessionClientError.api(
            .server(statusCode: 503)
        )
        let loader = StubTodoLoader(
            pageResults: [
                .success(
                    GitLabTodoPage(
                        todos: [first],
                        nextPageURL: nextPageURL,
                        totalCount: 2
                    )
                ),
                .failure(serverError),
                .failure(.api(.cancelled)),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: loader,
            apiAccess: .readWrite
        )

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(after: first)
        await model.retryNextPage()

        #expect(model.todos == [first])
        #expect(model.nextPageURL == nextPageURL)
        #expect(model.didFailNextPage)
        #expect(model.loadError == serverError)
    }

    @Test("Treats cancellation as a non-result")
    func ignoresCancellation() async {
        let loader = StubTodoLoader(
            pageResults: [
                .failure(.api(.cancelled)),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: loader,
            apiAccess: .readWrite
        )

        await model.loadIfNeeded()

        #expect(!model.hasLoaded)
        #expect(model.loadError == nil)
        #expect(model.todos.isEmpty)
        #expect(model.pendingBadgeCount == nil)
    }

    @Test("Exposes authentication failures")
    func exposesAuthenticationFailure() async {
        let loader = StubTodoLoader(
            pageResults: [
                .failure(.api(.unauthenticated)),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: loader,
            apiAccess: .readWrite
        )

        await model.loadIfNeeded()

        #expect(
            model.authenticationFailure
                == .api(.unauthenticated)
        )
    }
}

private actor StubTodoLoader:
    GitLabTodoLoading,
    GitLabTodoMutating
{
    private var pageResults: [
        Result<GitLabTodoPage, GitLabSessionClientError>
    ]
    private(set) var pageStates: [GitLabTodoState] = []
    private(set) var pageTargetFilters: [
        GitLabTodoTargetFilter
    ] = []
    private(set) var pageRequestURLs: [URL?] = []

    init(
        pageResults: [
            Result<GitLabTodoPage, GitLabSessionClientError>
        ]
    ) {
        self.pageResults = pageResults
    }

    func loadTodosPage(
        state: GitLabTodoState,
        targetFilter: GitLabTodoTargetFilter,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabTodoPage
    {
        pageStates.append(state)
        pageTargetFilters.append(targetFilter)
        pageRequestURLs.append(nextPageURL)
        guard !pageResults.isEmpty else {
            throw .api(.invalidResponse)
        }

        return try pageResults.removeFirst().get()
    }

    func markDone(
        id: Int
    ) async throws(GitLabSessionClientError) -> GitLabTodo {
        throw .api(.invalidResponse)
    }

    func markAllDone()
        async throws(GitLabSessionClientError)
    {
        throw .api(.invalidResponse)
    }
}
