import Foundation
import Observation

nonisolated enum GitLabSearchScopeStatus:
    Equatable,
    Sendable
{
    case idle
    case loading
    case loaded
    case unavailable(GitLabSessionClientError)
    case failed(GitLabSessionClientError)

    var isFailure: Bool {
        switch self {
        case .unavailable, .failed:
            true
        case .idle, .loading, .loaded:
            false
        }
    }
}

nonisolated struct GitLabSearchScopeState:
    Equatable,
    Sendable
{
    var results: [GitLabSearchResult]
    var nextPageURL: URL?
    var totalCount: Int?
    var status: GitLabSearchScopeStatus
    var isLoadingNextPage: Bool
    var nextPageError: GitLabSessionClientError?

    static var idle: Self {
        Self(
            results: [],
            nextPageURL: nil,
            totalCount: nil,
            status: .idle,
            isLoadingNextPage: false,
            nextPageError: nil
        )
    }

    static var loading: Self {
        Self(
            results: [],
            nextPageURL: nil,
            totalCount: nil,
            status: .loading,
            isLoadingNextPage: false,
            nextPageError: nil
        )
    }
}

@MainActor
@Observable
final class GitLabGlobalSearchModel {
    let accountID: GitLabAccountID

    var query = ""
    private(set) var recentQueries: [String] = []

    private let loader: any GitLabSearchLoading
    private let debounce:
        @Sendable () async throws -> Void
    private var states:
        [GitLabSearchScope: GitLabSearchScopeState]
    private var loadedNextPageURLs:
        [GitLabSearchScope: Set<URL>] = [:]
    private var requestGeneration = 0

    init(
        accountID: GitLabAccountID,
        loader: any GitLabSearchLoading,
        debounce:
            @escaping @Sendable () async throws
                -> Void = {
                    try await Task.sleep(
                        for: .milliseconds(300)
                    )
                }
    ) {
        self.accountID = accountID
        self.loader = loader
        self.debounce = debounce
        states = Self.emptyStates
    }

    var normalizedQuery: String {
        query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    var hasPartialResults: Bool {
        let values = Array(states.values)
        return values.contains {
            $0.status == .loaded
        } && values.contains {
            $0.status.isFailure
        }
    }

    var allScopesFailed: Bool {
        states.values.allSatisfy {
            $0.status.isFailure
        }
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        for state in states.values {
            switch state.status {
            case let .unavailable(error),
                 let .failed(error):
                if error.requiresReauthentication {
                    return error
                }
            case .idle, .loading, .loaded:
                break
            }

            if
                state.nextPageError?
                    .requiresReauthentication
                    == true
            {
                return state.nextPageError
            }
        }
        return nil
    }

    func state(
        for scope: GitLabSearchScope
    ) -> GitLabSearchScopeState {
        states[scope] ?? .idle
    }

    func resultID(
        for result: GitLabSearchResult
    ) -> GitLabSearchResultID {
        GitLabSearchResultID(
            accountID: accountID,
            resource: result.resourceID
        )
    }

    func useRecentQuery(_ query: String) {
        self.query = query
    }

    func search(_ query: String) async {
        self.query = query
        await runSearch(
            query: normalizedQuery,
            waitsForDebounce: true
        )
    }

    func refresh() async {
        await runSearch(
            query: normalizedQuery,
            waitsForDebounce: false
        )
    }

    func retry(
        _ scope: GitLabSearchScope
    ) async {
        let query = normalizedQuery
        guard !query.isEmpty else {
            return
        }

        let generation = requestGeneration
        states[scope] = .loading
        await loadFirstPage(
            scope: scope,
            query: query,
            generation: generation
        )
        recordRecentQueryIfNeeded(query)
    }

    func loadNextPage(
        for scope: GitLabSearchScope
    ) async {
        var state = state(for: scope)
        guard
            state.status == .loaded,
            let nextPageURL =
                state.nextPageURL,
            !state.isLoadingNextPage
        else {
            return
        }

        var loadedURLs =
            loadedNextPageURLs[scope]
                ?? []
        guard loadedURLs.insert(nextPageURL).inserted else {
            state.nextPageError =
                .api(.invalidResponse)
            states[scope] = state
            return
        }

        loadedNextPageURLs[scope] =
            loadedURLs
        state.isLoadingNextPage = true
        state.nextPageError = nil
        states[scope] = state

        let generation = requestGeneration
        let query = normalizedQuery

        do throws(GitLabSessionClientError) {
            let page = try await loader.loadPage(
                scope: scope,
                query: query,
                after: nextPageURL
            )
            guard
                isCurrent(
                    generation: generation,
                    query: query
                ),
                !Task.isCancelled
            else {
                return
            }
            guard
                page.results.allSatisfy({
                    $0.scope == scope
                })
            else {
                throw GitLabSessionClientError
                    .api(.invalidResponse)
            }

            state = self.state(for: scope)
            state.results = appendingUnique(
                page.results,
                to: state.results
            )
            state.nextPageURL =
                page.nextPageURL
            state.totalCount =
                page.totalCount
                    ?? state.totalCount
            state.isLoadingNextPage = false
            state.nextPageError = nil
            states[scope] = state
        } catch let error {
            guard
                isCurrent(
                    generation: generation,
                    query: query
                ),
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                return
            }

            loadedNextPageURLs[scope]?
                .remove(nextPageURL)
            state = self.state(for: scope)
            state.isLoadingNextPage = false
            state.nextPageError = error
            states[scope] = state
        }
    }

    private func runSearch(
        query: String,
        waitsForDebounce: Bool
    ) async {
        requestGeneration &+= 1
        let generation = requestGeneration
        loadedNextPageURLs.removeAll()

        guard !query.isEmpty else {
            states = Self.emptyStates
            return
        }

        states = Dictionary(
            uniqueKeysWithValues:
                GitLabSearchScope.allCases.map {
                    ($0, .loading)
                }
        )

        if waitsForDebounce {
            do {
                try await debounce()
            } catch {
                return
            }
        }

        guard
            isCurrent(
                generation: generation,
                query: query
            ),
            !Task.isCancelled
        else {
            return
        }

        await withTaskGroup(
            of: FirstPageOutcome.self
        ) { group in
            for scope in
                GitLabSearchScope.allCases
            {
                group.addTask {
                    do throws(
                        GitLabSessionClientError
                    ) {
                        return .success(
                            scope,
                            try await self.loader
                                .loadPage(
                                    scope: scope,
                                    query: query,
                                    after: nil
                                )
                        )
                    } catch let error {
                        return .failure(
                            scope,
                            error
                        )
                    }
                }
            }

            for await outcome in group {
                guard
                    isCurrent(
                        generation: generation,
                        query: query
                    ),
                    !Task.isCancelled
                else {
                    group.cancelAll()
                    continue
                }

                apply(
                    outcome,
                    generation: generation,
                    query: query
                )
            }
        }

        guard
            isCurrent(
                generation: generation,
                query: query
            ),
            !Task.isCancelled
        else {
            return
        }
        recordRecentQueryIfNeeded(query)
    }

    private func loadFirstPage(
        scope: GitLabSearchScope,
        query: String,
        generation: Int
    ) async {
        let outcome: FirstPageOutcome

        do throws(GitLabSessionClientError) {
            outcome = .success(
                scope,
                try await loader.loadPage(
                    scope: scope,
                    query: query,
                    after: nil
                )
            )
        } catch let error {
            outcome = .failure(
                scope,
                error
            )
        }

        guard
            isCurrent(
                generation: generation,
                query: query
            ),
            !Task.isCancelled
        else {
            return
        }
        apply(
            outcome,
            generation: generation,
            query: query
        )
    }

    private func apply(
        _ outcome: FirstPageOutcome,
        generation: Int,
        query: String
    ) {
        guard
            isCurrent(
                generation: generation,
                query: query
            )
        else {
            return
        }

        switch outcome {
        case let .success(scope, page):
            guard
                page.results.allSatisfy({
                    $0.scope == scope
                })
            else {
                states[scope] = failureState(
                    for: .api(.invalidResponse)
                )
                return
            }

            states[scope] =
                GitLabSearchScopeState(
                    results: page.results,
                    nextPageURL:
                        page.nextPageURL,
                    totalCount:
                        page.totalCount,
                    status: .loaded,
                    isLoadingNextPage: false,
                    nextPageError: nil
                )
        case let .failure(scope, error):
            guard
                error != .api(.cancelled)
            else {
                return
            }
            states[scope] =
                failureState(for: error)
        }
    }

    private func failureState(
        for error: GitLabSessionClientError
    ) -> GitLabSearchScopeState {
        var state =
            GitLabSearchScopeState.idle
        state.status = if isUnavailable(error) {
            .unavailable(error)
        } else {
            .failed(error)
        }
        return state
    }

    private func isUnavailable(
        _ error: GitLabSessionClientError
    ) -> Bool {
        switch error {
        case .api(.forbidden),
             .api(.notFound),
             .api(.validation):
            true
        default:
            false
        }
    }

    private func recordRecentQueryIfNeeded(
        _ query: String
    ) {
        guard states.values.contains(
            where: { $0.status == .loaded }
        ) else {
            return
        }

        recentQueries.removeAll {
            $0.compare(
                query,
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                ]
            ) == .orderedSame
        }
        recentQueries.insert(query, at: 0)
        if recentQueries.count > 5 {
            recentQueries.removeLast(
                recentQueries.count - 5
            )
        }
    }

    private func isCurrent(
        generation: Int,
        query: String
    ) -> Bool {
        requestGeneration == generation
            && normalizedQuery == query
    }

    private func appendingUnique(
        _ newResults: [GitLabSearchResult],
        to existing:
            [GitLabSearchResult]
    ) -> [GitLabSearchResult] {
        var identities = Set(
            existing.map(\.resourceID)
        )
        var results = existing

        for result in newResults
        where
            identities
                .insert(result.resourceID)
                .inserted
        {
            results.append(result)
        }
        return results
    }

    private static let emptyStates =
        Dictionary(
            uniqueKeysWithValues:
                GitLabSearchScope.allCases.map {
                    ($0, GitLabSearchScopeState.idle)
                }
        )
}

private nonisolated enum FirstPageOutcome:
    Sendable
{
    case success(
        GitLabSearchScope,
        GitLabSearchPage
    )
    case failure(
        GitLabSearchScope,
        GitLabSessionClientError
    )
}
