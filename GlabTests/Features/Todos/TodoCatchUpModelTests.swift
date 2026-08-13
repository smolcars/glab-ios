import Foundation
import Testing
@testable import Glab

@Suite("Todo Catch Up model")
@MainActor
struct TodoCatchUpModelTests {
    @Test("Keeps a partial pending count unknown")
    func keepsPartialCountUnknown() async throws {
        let secondPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/todos?page=2"
            )
        )
        let service = CatchUpTodoService(
            pages: [
                page(
                    [makeTestTodo(id: 1)],
                    nextPageURL: secondPageURL,
                    totalCount: nil
                ),
            ]
        )
        let todosModel = TodosModel(
            loader: service,
            mutator: service,
            apiAccess: .readWrite
        )
        let model = TodoCatchUpModel(
            todosModel: todosModel
        )

        await todosModel.loadIfNeeded()

        #expect(model.shouldShowHomeShortcut)
        #expect(model.homeShortcutCount == nil)
    }

    @Test("Loads every pending page before starting the deck")
    func loadsAllPendingPages() async throws {
        let secondPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/todos?page=2"
            )
        )
        let service = CatchUpTodoService(
            pages: [
                page(
                    [makeTestTodo(id: 1)],
                    nextPageURL: secondPageURL,
                    totalCount: 3
                ),
                page(
                    [
                        makeTestTodo(id: 2),
                        makeTestTodo(id: 3),
                    ],
                    totalCount: 3
                ),
            ]
        )
        let todosModel = TodosModel(
            loader: service,
            mutator: service,
            apiAccess: .readWrite
        )
        let model = TodoCatchUpModel(
            todosModel: todosModel
        )

        await model.startIfNeeded()

        #expect(model.phase == .active)
        #expect(model.visibleTodos.map(\.id) == [1, 2, 3])
        #expect(model.remainingCount == 3)
        #expect(
            await service.requestedPages
                == [nil, secondPageURL]
        )
    }

    @Test("Keeping a Todo finishes the session without completing it")
    func keepsTodoPending() async {
        let todo = makeTestTodo(id: 1)
        let service = CatchUpTodoService(
            pages: [page([todo], totalCount: 1)]
        )
        let todosModel = TodosModel(
            loader: service,
            mutator: service,
            apiAccess: .readWrite
        )
        let model = TodoCatchUpModel(
            todosModel: todosModel
        )
        await model.startIfNeeded()

        model.keepCurrent()

        #expect(model.phase == .completed)
        #expect(model.keptCount == 1)
        #expect(model.completedCount == 0)
        #expect(todosModel.pendingTodos == [todo])
        #expect(!model.shouldShowHomeShortcut)
    }

    @Test("Completing a Todo updates the shared inbox and summary")
    func completesTodo() async {
        let pending = makeTestTodo(id: 1)
        let completed = makeTestTodo(
            id: 1,
            state: .done
        )
        let service = CatchUpTodoService(
            pages: [page([pending], totalCount: 1)],
            completionResults: [.success(completed)]
        )
        let todosModel = TodosModel(
            loader: service,
            mutator: service,
            apiAccess: .readWrite
        )
        let model = TodoCatchUpModel(
            todosModel: todosModel
        )
        await model.startIfNeeded()

        await model.markCurrentDone()

        #expect(model.phase == .completed)
        #expect(model.completedCount == 1)
        #expect(model.keptCount == 0)
        #expect(todosModel.pendingTodos.isEmpty)
        #expect(todosModel.pendingBadgeCount == 0)
        #expect(await service.completedIDs == [1])
    }

    @Test("A failed completion restores the same card")
    func restoresFailedCompletion() async {
        let pending = makeTestTodo(id: 1)
        let failure = GitLabSessionClientError.api(
            .server(statusCode: 503)
        )
        let service = CatchUpTodoService(
            pages: [page([pending], totalCount: 1)],
            completionResults: [.failure(failure)]
        )
        let todosModel = TodosModel(
            loader: service,
            mutator: service,
            apiAccess: .readWrite
        )
        let model = TodoCatchUpModel(
            todosModel: todosModel
        )
        await model.startIfNeeded()

        await model.markCurrentDone()

        #expect(model.phase == .active)
        #expect(model.currentTodo == pending)
        #expect(model.remainingCount == 1)
        #expect(model.completionFailure == failure)
        #expect(model.completedCount == 0)
    }

    @Test("Retry resumes a failed page without losing the deck")
    func retriesFailedPage() async throws {
        let secondPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/todos?page=2"
            )
        )
        let failure = GitLabSessionClientError.api(
            .server(statusCode: 503)
        )
        let service = CatchUpTodoService(
            pageResults: [
                .success(
                    page(
                        [makeTestTodo(id: 1)],
                        nextPageURL: secondPageURL,
                        totalCount: 2
                    )
                ),
                .failure(failure),
                .success(
                    page(
                        [makeTestTodo(id: 2)],
                        totalCount: 2
                    )
                ),
            ]
        )
        let todosModel = TodosModel(
            loader: service,
            mutator: service,
            apiAccess: .readWrite
        )
        let model = TodoCatchUpModel(
            todosModel: todosModel
        )

        await model.startIfNeeded()
        #expect(model.phase == .failed(failure))

        await model.startIfNeeded()

        #expect(model.phase == .active)
        #expect(model.visibleTodos.map(\.id) == [1, 2])
        #expect(
            await service.requestedPages
                == [nil, secondPageURL, secondPageURL]
        )
    }

    private func page(
        _ todos: [GitLabTodo],
        nextPageURL: URL? = nil,
        totalCount: Int?
    ) -> GitLabTodoPage {
        GitLabTodoPage(
            todos: todos,
            nextPageURL: nextPageURL,
            totalCount: totalCount
        )
    }
}

private actor CatchUpTodoService:
    GitLabTodoLoading,
    GitLabTodoMutating
{
    private var pageResults: [
        Result<GitLabTodoPage, GitLabSessionClientError>
    ]
    private var completionResults: [
        Result<GitLabTodo, GitLabSessionClientError>
    ]
    private(set) var requestedPages: [URL?] = []
    private(set) var completedIDs: [Int] = []

    init(
        pages: [GitLabTodoPage],
        completionResults: [
            Result<
                GitLabTodo,
                GitLabSessionClientError
            >
        ] = []
    ) {
        pageResults = pages.map(Result.success)
        self.completionResults = completionResults
    }

    init(
        pageResults: [
            Result<
                GitLabTodoPage,
                GitLabSessionClientError
            >
        ]
    ) {
        self.pageResults = pageResults
        completionResults = []
    }

    func loadTodosPage(
        state: GitLabTodoState,
        targetFilter: GitLabTodoTargetFilter,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabTodoPage
    {
        requestedPages.append(nextPageURL)
        guard !pageResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try pageResults.removeFirst().get()
    }

    func markDone(
        id: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabTodo
    {
        completedIDs.append(id)
        guard !completionResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try completionResults.removeFirst().get()
    }

    func markAllDone()
        async throws(GitLabSessionClientError)
    {
        throw .api(.invalidResponse)
    }
}
