import Foundation
import Testing
@testable import Glab

@Suite("Todo completion model")
@MainActor
struct TodosMutationModelTests {
    @Test("Single completion hides immediately and appears in done Todos")
    func completesSingleTodoOptimistically() async throws {
        let pending = makeTestTodo(id: 1)
        let completed = makeTestTodo(
            id: 1,
            state: .done
        )
        let loader = MutationTodoLoader(
            pageResults: [
                .success(page([pending], totalCount: 1)),
                .success(page([], totalCount: 0)),
            ]
        )
        let mutator = ControlledTodoMutator(
            singleResult: .success(completed)
        )
        let model = TodosModel(
            loader: loader,
            mutator: mutator,
            apiAccess: .readWrite
        )
        await model.loadIfNeeded()

        let task = Task {
            await model.markDone(pending)
        }
        await mutator.waitForSingleStart()

        #expect(model.todos.isEmpty)
        #expect(model.pendingBadgeCount == 0)
        #expect(model.isCompleting(todoID: 1))

        await mutator.releaseSingle()
        await task.value

        #expect(!model.isCompleting(todoID: 1))
        #expect(model.mutationFailure == nil)
        model.selectedState = .done
        await model.loadIfNeeded()
        #expect(model.todos == [completed])
    }

    @Test("A server total is adjusted once and reconciled after refresh")
    func reconcilesPartialPendingCount() async throws {
        let pending = makeTestTodo(id: 1)
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "todos?page=2"
            )
        )
        let loader = MutationTodoLoader(
            pageResults: [
                .success(
                    page(
                        [pending],
                        nextPageURL: nextPageURL,
                        totalCount: 27
                    )
                ),
                .success(page([], totalCount: 26)),
            ]
        )
        let mutator = SequencedTodoMutator(
            singleResults: [
                .success(
                    makeTestTodo(id: 1, state: .done)
                ),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: mutator,
            apiAccess: .readWrite
        )
        await model.loadIfNeeded()

        await model.markDone(pending)
        #expect(model.pendingBadgeCount == 26)

        await model.refresh()
        #expect(model.pendingBadgeCount == 26)
    }

    @Test("Single failure rolls back and retains retry context")
    func rollsBackSingleFailureAndRetries() async {
        let pending = makeTestTodo(id: 1)
        let completed = makeTestTodo(
            id: 1,
            state: .done
        )
        let failure = GitLabSessionClientError.api(
            .server(statusCode: 503)
        )
        let loader = MutationTodoLoader(
            pageResults: [
                .success(page([pending], totalCount: 1)),
            ]
        )
        let mutator = SequencedTodoMutator(
            singleResults: [
                .failure(failure),
                .success(completed),
            ]
        )
        let model = TodosModel(
            loader: loader,
            mutator: mutator,
            apiAccess: .readWrite
        )
        await model.loadIfNeeded()

        await model.markDone(pending)

        #expect(model.todos == [pending])
        #expect(model.pendingBadgeCount == 1)
        #expect(
            model.mutationFailure
                == .markDone(id: 1, error: failure)
        )

        await model.retryFailedMutation()

        #expect(model.todos.isEmpty)
        #expect(model.pendingBadgeCount == 0)
        #expect(model.mutationFailure == nil)
        #expect(await mutator.singleIDs == [1, 1])
    }

    @Test("Duplicate single completion taps send one request")
    func ignoresDuplicateSingleCompletion() async {
        let pending = makeTestTodo(id: 1)
        let loader = MutationTodoLoader(
            pageResults: [
                .success(page([pending], totalCount: 1)),
            ]
        )
        let mutator = ControlledTodoMutator(
            singleResult: .success(
                makeTestTodo(id: 1, state: .done)
            )
        )
        let model = TodosModel(
            loader: loader,
            mutator: mutator,
            apiAccess: .readWrite
        )
        await model.loadIfNeeded()

        let first = Task {
            await model.markDone(pending)
        }
        await mutator.waitForSingleStart()
        await model.markDone(pending)
        await mutator.releaseSingle()
        await first.value

        #expect(await mutator.singleIDs == [1])
    }

    @Test("Mark all hides pending Todos and reloads done Todos")
    func marksAllDoneOptimistically() async {
        let first = makeTestTodo(id: 1)
        let second = makeTestTodo(id: 2)
        let completedFirst = makeTestTodo(
            id: 1,
            state: .done
        )
        let completedSecond = makeTestTodo(
            id: 2,
            state: .done
        )
        let loader = MutationTodoLoader(
            pageResults: [
                .success(
                    page(
                        [first, second],
                        totalCount: 2
                    )
                ),
                .success(
                    page(
                        [completedFirst, completedSecond],
                        totalCount: 2
                    )
                ),
            ]
        )
        let mutator = ControlledTodoMutator(
            allResult: .success(())
        )
        let model = TodosModel(
            loader: loader,
            mutator: mutator,
            apiAccess: .readWrite
        )
        await model.loadIfNeeded()

        let task = Task {
            await model.markAllDone()
        }
        await mutator.waitForAllStart()

        #expect(model.todos.isEmpty)
        #expect(model.pendingBadgeCount == 0)
        #expect(model.isMarkingAllDone)

        await mutator.releaseAll()
        await task.value

        #expect(!model.isMarkingAllDone)
        #expect(model.mutationFailure == nil)
        model.selectedState = .done
        await model.loadIfNeeded()
        #expect(
            model.todos
                == [completedFirst, completedSecond]
        )
        #expect(await mutator.markAllCallCount == 1)
    }

    @Test("Mark-all failure restores only pending presentation")
    func rollsBackMarkAllFailure() async {
        let first = makeTestTodo(id: 1)
        let second = makeTestTodo(id: 2)
        let failure = GitLabSessionClientError.api(
            .forbidden
        )
        let loader = MutationTodoLoader(
            pageResults: [
                .success(
                    page(
                        [first, second],
                        totalCount: 2
                    )
                ),
            ]
        )
        let mutator = ControlledTodoMutator(
            allResult: .failure(failure)
        )
        let model = TodosModel(
            loader: loader,
            mutator: mutator,
            apiAccess: .readWrite
        )
        await model.loadIfNeeded()

        let task = Task {
            await model.markAllDone()
        }
        await mutator.waitForAllStart()
        #expect(model.todos.isEmpty)
        await mutator.releaseAll()
        await task.value

        #expect(model.todos == [first, second])
        #expect(model.pendingBadgeCount == 2)
        #expect(
            model.mutationFailure
                == .markAllDone(error: failure)
        )
    }

    @Test("Mutation overlay survives filters and a stale refresh")
    func preservesOverlayAcrossFilterAndRefresh() async {
        let pending = makeTestTodo(
            id: 1,
            targetType: .issue
        )
        let loader = MutationTodoLoader(
            pageResults: [
                .success(page([pending], totalCount: 1)),
                .success(page([pending], totalCount: 1)),
                .success(page([pending], totalCount: 1)),
            ]
        )
        let mutator = ControlledTodoMutator(
            singleResult: .success(
                makeTestTodo(
                    id: 1,
                    state: .done,
                    targetType: .issue
                )
            )
        )
        let model = TodosModel(
            loader: loader,
            mutator: mutator,
            apiAccess: .readWrite
        )
        await model.loadIfNeeded()

        let task = Task {
            await model.markDone(pending)
        }
        await mutator.waitForSingleStart()
        await model.refresh()
        #expect(model.todos.isEmpty)
        #expect(model.pendingBadgeCount == 0)

        model.selectedTargetFilter = .issues
        await model.loadIfNeeded()
        #expect(model.todos.isEmpty)

        await mutator.releaseSingle()
        await task.value
        #expect(model.todos.isEmpty)
    }

    @Test("Read-only sessions expose capability and never call the mutator")
    func disablesReadOnlyCompletion() async {
        let pending = makeTestTodo(id: 1)
        let loader = MutationTodoLoader(
            pageResults: [
                .success(page([pending], totalCount: 1)),
            ]
        )
        let mutator = SequencedTodoMutator()
        let model = TodosModel(
            loader: loader,
            mutator: mutator,
            apiAccess: .readOnly
        )
        await model.loadIfNeeded()

        #expect(!model.canComplete)
        await model.markDone(pending)
        await model.markAllDone()

        #expect(model.todos == [pending])
        #expect(await mutator.singleIDs.isEmpty)
        #expect(await mutator.markAllCallCount == 0)
    }

    @Test("Cancellation rolls back silently")
    func rollsBackCancellationSilently() async {
        let pending = makeTestTodo(id: 1)
        let loader = MutationTodoLoader(
            pageResults: [
                .success(page([pending], totalCount: 1)),
            ]
        )
        let mutator = ControlledTodoMutator(
            singleResult: .success(
                makeTestTodo(id: 1, state: .done)
            )
        )
        let model = TodosModel(
            loader: loader,
            mutator: mutator,
            apiAccess: .readWrite
        )
        await model.loadIfNeeded()

        let task = Task {
            await model.markDone(pending)
        }
        await mutator.waitForSingleStart()
        task.cancel()
        await mutator.releaseSingle()
        await task.value

        #expect(model.todos == [pending])
        #expect(model.pendingBadgeCount == 1)
        #expect(model.mutationFailure == nil)
    }

    @Test("Mutation authentication failures use existing session recovery")
    func exposesMutationAuthenticationFailure() async {
        let pending = makeTestTodo(id: 1)
        let failure =
            GitLabSessionClientError.api(.unauthenticated)
        let loader = MutationTodoLoader(
            pageResults: [
                .success(page([pending], totalCount: 1)),
            ]
        )
        let mutator = SequencedTodoMutator(
            singleResults: [.failure(failure)]
        )
        let model = TodosModel(
            loader: loader,
            mutator: mutator,
            apiAccess: .readWrite
        )
        await model.loadIfNeeded()

        await model.markDone(pending)

        #expect(model.authenticationFailure == failure)
        #expect(model.todos == [pending])
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

private actor MutationTodoLoader: GitLabTodoLoading {
    private var pageResults: [
        Result<GitLabTodoPage, GitLabSessionClientError>
    ]

    init(
        pageResults: [
            Result<
                GitLabTodoPage,
                GitLabSessionClientError
            >
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
        guard !pageResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try pageResults.removeFirst().get()
    }
}

private actor SequencedTodoMutator:
    GitLabTodoMutating
{
    private var singleResults: [
        Result<GitLabTodo, GitLabSessionClientError>
    ]
    private var allResults: [
        Result<Void, GitLabSessionClientError>
    ]
    private(set) var singleIDs: [Int] = []
    private(set) var markAllCallCount = 0

    init(
        singleResults: [
            Result<
                GitLabTodo,
                GitLabSessionClientError
            >
        ] = [],
        allResults: [
            Result<Void, GitLabSessionClientError>
        ] = []
    ) {
        self.singleResults = singleResults
        self.allResults = allResults
    }

    func markDone(
        id: Int
    ) async throws(GitLabSessionClientError) -> GitLabTodo {
        singleIDs.append(id)
        guard !singleResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try singleResults.removeFirst().get()
    }

    func markAllDone()
        async throws(GitLabSessionClientError)
    {
        markAllCallCount += 1
        guard !allResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        try allResults.removeFirst().get()
    }
}

private actor ControlledTodoMutator:
    GitLabTodoMutating
{
    private let singleResult:
        Result<GitLabTodo, GitLabSessionClientError>
    private let allResult:
        Result<Void, GitLabSessionClientError>
    private var singleRelease:
        CheckedContinuation<Void, Never>?
    private var allRelease:
        CheckedContinuation<Void, Never>?
    private var singleStartWaiters: [
        CheckedContinuation<Void, Never>
    ] = []
    private var allStartWaiters: [
        CheckedContinuation<Void, Never>
    ] = []
    private(set) var singleIDs: [Int] = []
    private(set) var markAllCallCount = 0

    init(
        singleResult:
            Result<
                GitLabTodo,
                GitLabSessionClientError
            > = .failure(.api(.invalidResponse)),
        allResult:
            Result<
                Void,
                GitLabSessionClientError
            > = .failure(.api(.invalidResponse))
    ) {
        self.singleResult = singleResult
        self.allResult = allResult
    }

    func markDone(
        id: Int
    ) async throws(GitLabSessionClientError) -> GitLabTodo {
        singleIDs.append(id)
        let waiters = singleStartWaiters
        singleStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation {
            singleRelease = $0
        }
        return try singleResult.get()
    }

    func markAllDone()
        async throws(GitLabSessionClientError)
    {
        markAllCallCount += 1
        let waiters = allStartWaiters
        allStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation {
            allRelease = $0
        }
        try allResult.get()
    }

    func waitForSingleStart() async {
        guard singleIDs.isEmpty else {
            return
        }
        await withCheckedContinuation {
            singleStartWaiters.append($0)
        }
    }

    func waitForAllStart() async {
        guard markAllCallCount == 0 else {
            return
        }
        await withCheckedContinuation {
            allStartWaiters.append($0)
        }
    }

    func releaseSingle() {
        singleRelease?.resume()
        singleRelease = nil
    }

    func releaseAll() {
        allRelease?.resume()
        allRelease = nil
    }
}
