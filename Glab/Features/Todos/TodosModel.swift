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
    @ObservationIgnored
    private let loader: any GitLabTodoLoading
    @ObservationIgnored
    private var cachedModels: [
        GitLabTodoQuery: GitLabTodosPageModel
    ]

    init(
        loader: any GitLabTodoLoading
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
        activeModel.items
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
        activeModel.authenticationFailure
    }

    var pendingBadgeCount: Int? {
        let query = GitLabTodoQuery(
            state: .pending,
            targetFilter: .all
        )
        return cachedModels[query]?.reliableItemCount
    }

    func loadIfNeeded() async {
        await activeModel.loadIfNeeded()
    }

    func refresh() async {
        await activeModel.refresh()
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
}
