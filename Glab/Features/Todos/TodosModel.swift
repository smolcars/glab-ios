import Foundation
import Observation

nonisolated struct GitLabTodoQuery:
    Equatable,
    Hashable,
    Sendable
{
    let state: GitLabTodoState
    let targetFilter: GitLabTodoTargetFilter
}

nonisolated enum GitLabTodoMutationFailure:
    Equatable,
    Sendable
{
    case markDone(
        id: Int,
        error: GitLabSessionClientError
    )
    case markAllDone(
        error: GitLabSessionClientError
    )

    var error: GitLabSessionClientError {
        switch self {
        case let .markDone(_, error),
             let .markAllDone(error):
            error
        }
    }
}

typealias GitLabTodosPageModel =
    GitLabPaginatedResourceModel<
        GitLabTodo,
        Int
    >

extension GitLabPaginatedResourceModel
where
    Item == GitLabTodo,
    Identity == Int
{
    convenience init(
        query: GitLabTodoQuery,
        loader: any GitLabTodoLoading
    ) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<GitLabTodo> in
                let page = try await loader.loadTodosPage(
                    state: query.state,
                    targetFilter: query.targetFilter,
                    after: nextPageURL
                )
                return GitLabResourcePage(
                    items: page.todos,
                    nextPageURL: page.nextPageURL,
                    totalCount: page.totalCount
                )
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @escaping @Sendable (
                            GitLabResourcePageEvent<
                                GitLabTodo
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader.loadTodosFirstPage(
                    state: query.state,
                    targetFilter: query.targetFilter,
                    refreshBehavior: refreshBehavior,
                    onPage: onPage
                )
            },
            identity: { $0.id },
            searchValues: {
                [
                    $0.title,
                    $0.displayBody,
                    $0.projectTitle,
                    $0.authorTitle,
                    $0.action.title,
                    $0.targetType.title,
                ]
                .compactMap(\.self)
            }
        )
    }
}

@MainActor
@Observable
final class TodosModel {
    var selectedState = GitLabTodoState.pending {
        didSet {
            activateSelectedQuery()
        }
    }
    var selectedTargetFilter =
        GitLabTodoTargetFilter.all
    {
        didSet {
            activateSelectedQuery()
        }
    }

    private(set) var activeModel: GitLabTodosPageModel
    private(set) var completingTodoIDs: Set<Int> = []
    private(set) var isMarkingAllDone = false
    private(set) var mutationFailure:
        GitLabTodoMutationFailure?
    @ObservationIgnored
    private let loader: any GitLabTodoLoading
    @ObservationIgnored
    private let mutator: any GitLabTodoMutating
    @ObservationIgnored
    private let apiAccess: GitLabAPIAccess
    @ObservationIgnored
    private var cachedModels: [
        GitLabTodoQuery: GitLabTodosPageModel
    ]
    private var hiddenPendingTodoIDs: Set<Int> = []
    private var pendingBadgeAdjustmentIDs:
        Set<Int> = []
    private var completedTodosByID:
        [Int: GitLabTodo] = [:]
    private var completedTodoOrder: [Int] = []
    @ObservationIgnored
    private var doneQueriesNeedingRefresh:
        Set<GitLabTodoQuery> = []
    private var markAllSnapshotTodoIDs: Set<Int> = []
    private var hidesAllPendingTodos = false

    init(
        loader: any GitLabTodoLoading,
        mutator: any GitLabTodoMutating,
        apiAccess: GitLabAPIAccess
    ) {
        let query = GitLabTodoQuery(
            state: .pending,
            targetFilter: .all
        )
        let model = GitLabTodosPageModel(
            query: query,
            loader: loader
        )

        self.loader = loader
        self.mutator = mutator
        self.apiAccess = apiAccess
        activeModel = model
        cachedModels = [query: model]
    }

    var query: GitLabTodoQuery {
        GitLabTodoQuery(
            state: selectedState,
            targetFilter: selectedTargetFilter
        )
    }

    var todos: [GitLabTodo] {
        switch selectedState {
        case .pending:
            guard !hidesAllPendingTodos else {
                return []
            }
            return activeModel.items.filter {
                !hiddenPendingTodoIDs.contains($0.id)
            }
        case .done:
            let overlays = completedTodoOrder
                .compactMap { completedTodosByID[$0] }
                .filter(matchesSelectedTarget)
            let overlayIDs = Set(overlays.map(\.id))
            return overlays
                + activeModel.items.filter {
                    !overlayIDs.contains($0.id)
                }
        }
    }

    var nextPageURL: URL? {
        activeModel.nextPageURL
    }

    var loadError: GitLabSessionClientError? {
        activeModel.loadError
    }

    var isLoadingInitial: Bool {
        activeModel.isLoadingInitial
    }

    var isRefreshing: Bool {
        activeModel.isRefreshing
    }

    var isLoadingNextPage: Bool {
        activeModel.isLoadingNextPage
    }

    var didFailRefresh: Bool {
        activeModel.didFailRefresh
    }

    var didFailNextPage: Bool {
        activeModel.didFailNextPage
    }

    var hasLoaded: Bool {
        activeModel.hasLoaded
    }

    var authenticationFailure: GitLabSessionClientError? {
        if let failure = activeModel.authenticationFailure {
            return failure
        }
        guard
            mutationFailure?.error
                .requiresReauthentication == true
        else {
            return nil
        }
        return mutationFailure?.error
    }

    var pendingBadgeCount: Int? {
        let query = GitLabTodoQuery(
            state: .pending,
            targetFilter: .all
        )
        guard
            let count =
                cachedModels[query]?.reliableItemCount
        else {
            return hidesAllPendingTodos ? 0 : nil
        }
        guard !hidesAllPendingTodos else {
            return 0
        }
        return max(
            0,
            count - pendingBadgeAdjustmentIDs.count
        )
    }

    var canComplete: Bool {
        apiAccess.canWrite
    }

    var canMarkAllDone: Bool {
        canComplete
            && selectedState == .pending
            && !todos.isEmpty
            && completingTodoIDs.isEmpty
            && !isMarkingAllDone
    }

    func isCompleting(
        todoID: Int
    ) -> Bool {
        completingTodoIDs.contains(todoID)
    }

    func loadIfNeeded() async {
        let requestedQuery = query
        let requestedModel = activeModel
        if
            doneQueriesNeedingRefresh.contains(requestedQuery),
            requestedModel.hasLoaded
        {
            await refresh(
                query: requestedQuery,
                model: requestedModel
            )
        } else {
            let previousRevision =
                requestedModel.contentRevision
            await requestedModel.loadIfNeeded()
            guard
                requestedModel.contentRevision
                    != previousRevision
            else {
                return
            }
            reconcileSuccessfulReplace(
                query: requestedQuery,
                model: requestedModel
            )
        }
    }

    func refresh() async {
        await refresh(
            query: query,
            model: activeModel
        )
    }

    private func refresh(
        query refreshedQuery: GitLabTodoQuery,
        model refreshedModel: GitLabTodosPageModel
    ) async {
        let previousRevision =
            refreshedModel.contentRevision
        await refreshedModel.refresh()
        guard
            refreshedModel.contentRevision
                != previousRevision
        else {
            return
        }
        reconcileSuccessfulReplace(
            query: refreshedQuery,
            model: refreshedModel
        )
    }

    func loadNextPageIfNeeded(
        after todo: GitLabTodo
    ) async {
        await activeModel.loadNextPageIfNeeded(
            after: todo
        )
    }

    func retryNextPage() async {
        await activeModel.retryNextPage()
    }

    func markDone(
        _ todo: GitLabTodo
    ) async {
        guard canComplete else {
            mutationFailure = .markDone(
                id: todo.id,
                error: .insufficientAccess(
                    required: .write
                )
            )
            return
        }
        guard
            todo.state == .pending,
            !isMarkingAllDone,
            !hidesAllPendingTodos,
            !hiddenPendingTodoIDs.contains(todo.id)
        else {
            return
        }

        mutationFailure = nil
        completingTodoIDs.insert(todo.id)
        hiddenPendingTodoIDs.insert(todo.id)
        pendingBadgeAdjustmentIDs.insert(todo.id)

        do {
            let completed = try await mutator.markDone(
                id: todo.id
            )
            guard !Task.isCancelled else {
                rollBackSingleCompletion(todoID: todo.id)
                return
            }

            retainCompletedTodo(completed)
            markLoadedDoneQueriesForRefresh()
            completingTodoIDs.remove(todo.id)
        } catch {
            rollBackSingleCompletion(todoID: todo.id)
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                return
            }
            mutationFailure = .markDone(
                id: todo.id,
                error: error
            )
        }
    }

    func markAllDone() async {
        guard canComplete else {
            mutationFailure = .markAllDone(
                error: .insufficientAccess(
                    required: .write
                )
            )
            return
        }
        guard
            selectedState == .pending,
            !isMarkingAllDone,
            completingTodoIDs.isEmpty,
            !todos.isEmpty
        else {
            return
        }

        mutationFailure = nil
        isMarkingAllDone = true
        markAllSnapshotTodoIDs =
            currentlyCachedPendingTodoIDs
                .subtracting(hiddenPendingTodoIDs)
        hiddenPendingTodoIDs.formUnion(
            markAllSnapshotTodoIDs
        )
        pendingBadgeAdjustmentIDs.formUnion(
            markAllSnapshotTodoIDs
        )
        hidesAllPendingTodos = true

        do {
            try await mutator.markAllDone()
            guard !Task.isCancelled else {
                rollBackMarkAllCompletion()
                return
            }

            markLoadedDoneQueriesForRefresh()
            markAllSnapshotTodoIDs.removeAll()
            isMarkingAllDone = false
        } catch {
            rollBackMarkAllCompletion()
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                return
            }
            mutationFailure = .markAllDone(
                error: error
            )
        }
    }

    func retryFailedMutation() async {
        guard let failure = mutationFailure else {
            return
        }
        switch failure {
        case let .markDone(id, _):
            guard let todo = pendingTodo(id: id) else {
                mutationFailure = nil
                return
            }
            await markDone(todo)
        case .markAllDone:
            await markAllDone()
        }
    }

    private func activateSelectedQuery() {
        if let cachedModel = cachedModels[query] {
            activeModel = cachedModel
            return
        }

        let model = GitLabTodosPageModel(
            query: query,
            loader: loader
        )
        cachedModels[query] = model
        activeModel = model
    }

    private func matchesSelectedTarget(
        _ todo: GitLabTodo
    ) -> Bool {
        switch selectedTargetFilter {
        case .all:
            true
        case .issues:
            todo.targetType == .issue
        case .mergeRequests:
            todo.targetType == .mergeRequest
        }
    }

    private func retainCompletedTodo(
        _ todo: GitLabTodo
    ) {
        if completedTodosByID[todo.id] == nil {
            completedTodoOrder.append(todo.id)
        }
        completedTodosByID[todo.id] = todo
    }

    private func markLoadedDoneQueriesForRefresh() {
        for (query, model) in cachedModels
        where query.state == .done && model.hasLoaded
        {
            doneQueriesNeedingRefresh.insert(query)
        }
    }

    private func reconcileSuccessfulReplace(
        query replacedQuery: GitLabTodoQuery,
        model replacedModel: GitLabTodosPageModel
    ) {
        guard
            replacedModel.hasLoaded,
            replacedModel.loadError == nil
        else {
            return
        }
        doneQueriesNeedingRefresh.remove(replacedQuery)

        guard replacedQuery.state == .pending else {
            return
        }
        if hidesAllPendingTodos && !isMarkingAllDone {
            hidesAllPendingTodos = false
        }
        guard
            replacedQuery.targetFilter == .all,
            !hidesAllPendingTodos
        else {
            return
        }

        let hiddenLoadedIDs = Set(
            replacedModel.items.map(\.id)
        )
        .intersection(hiddenPendingTodoIDs)
        pendingBadgeAdjustmentIDs =
            hiddenLoadedIDs.union(completingTodoIDs)
    }

    private func rollBackSingleCompletion(
        todoID: Int
    ) {
        completingTodoIDs.remove(todoID)
        hiddenPendingTodoIDs.remove(todoID)
        pendingBadgeAdjustmentIDs.remove(todoID)
    }

    private func rollBackMarkAllCompletion() {
        isMarkingAllDone = false
        hidesAllPendingTodos = false
        hiddenPendingTodoIDs.subtract(
            markAllSnapshotTodoIDs
        )
        pendingBadgeAdjustmentIDs.subtract(
            markAllSnapshotTodoIDs
        )
        markAllSnapshotTodoIDs.removeAll()
    }

    private var currentlyCachedPendingTodoIDs:
        Set<Int>
    {
        var todoIDs: Set<Int> = []
        for (query, model) in cachedModels
        where query.state == .pending
        {
            todoIDs.formUnion(model.items.map(\.id))
        }
        return todoIDs
    }

    private func pendingTodo(
        id: Int
    ) -> GitLabTodo? {
        for (query, model) in cachedModels
        where query.state == .pending
        {
            if let todo = model.items.first(
                where: { $0.id == id }
            ) {
                return todo
            }
        }
        return nil
    }
}
