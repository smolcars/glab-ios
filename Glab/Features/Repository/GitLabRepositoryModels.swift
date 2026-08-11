import Foundation
import Observation

typealias GitLabRepositoryDirectoryModel =
    GitLabPaginatedResourceModel<
        GitLabRepositoryEntry,
        String
    >

extension GitLabPaginatedResourceModel
where
    Item == GitLabRepositoryEntry,
    Identity == String
{
    convenience init(
        projectID: Int,
        ref: String,
        path: String,
        loader: any GitLabRepositoryBrowsing
    ) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<
                    GitLabRepositoryEntry
                > in
                let page = try await loader
                    .loadTreePage(
                        projectID: projectID,
                        ref: ref,
                        path: path,
                        after: nextPageURL
                    )
                return GitLabResourcePage(
                    items: page.entries,
                    nextPageURL:
                        page.nextPageURL
                )
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @escaping @Sendable (
                            GitLabResourcePageEvent<
                                GitLabRepositoryEntry
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader
                    .loadTreeFirstPage(
                        projectID: projectID,
                        ref: ref,
                        path: path,
                        refreshBehavior:
                            refreshBehavior,
                        onPage: onPage
                    )
            },
            identity: \GitLabRepositoryEntry.id,
            searchValues: {
                [$0.name, $0.path]
            }
        )
    }

    var sortedRepositoryEntries:
        [GitLabRepositoryEntry]
    {
        displayedItems.sorted {
            if
                $0.sortPriority
                    != $1.sortPriority
            {
                return $0.sortPriority
                    < $1.sortPriority
            }
            return $0.name.localizedStandardCompare(
                $1.name
            ) == .orderedAscending
        }
    }
}

typealias GitLabRepositoryBranchesModel =
    GitLabPaginatedResourceModel<
        GitLabRepositoryBranch,
        String
    >

extension GitLabPaginatedResourceModel
where
    Item == GitLabRepositoryBranch,
    Identity == String
{
    convenience init(
        projectID: Int,
        search: String? = nil,
        loader: any GitLabRepositoryBrowsing
    ) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<
                    GitLabRepositoryBranch
                > in
                let page = try await loader
                    .loadBranchesPage(
                        projectID: projectID,
                        search: search,
                        after: nextPageURL
                    )
                return GitLabResourcePage(
                    items: page.branches,
                    nextPageURL:
                        page.nextPageURL
                )
            },
            identity: \GitLabRepositoryBranch.name,
            searchValues: { [$0.name] }
        )
    }

    var sortedRepositoryBranches:
        [GitLabRepositoryBranch]
    {
        displayedItems.sorted {
            if $0.isDefault != $1.isDefault {
                return $0.isDefault
            }
            return $0.name.localizedStandardCompare(
                $1.name
            ) == .orderedAscending
        }
    }
}

@MainActor
@Observable
final class GitLabRepositorySearchModel {
    private(set) var results:
        [GitLabRepositorySearchResult] = []
    private(set) var nextPageURL: URL?
    private(set) var error:
        GitLabSessionClientError?
    private(set) var isSearching = false
    private(set) var isLoadingNextPage = false
    private(set) var didSearch = false

    private let projectID: Int
    private let ref: String
    private let loader:
        any GitLabRepositoryBrowsing
    private var currentQuery = ""

    init(
        projectID: Int,
        ref: String,
        loader: any GitLabRepositoryBrowsing
    ) {
        self.projectID = projectID
        self.ref = ref
        self.loader = loader
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        guard
            error?.requiresReauthentication
                == true
        else {
            return nil
        }
        return error
    }

    func search(_ query: String) async {
        let query = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            clear()
            return
        }

        currentQuery = query
        isSearching = true
        isLoadingNextPage = false
        error = nil
        nextPageURL = nil
        results = []
        didSearch = false

        do {
            let page = try await loader
                .loadSearchPage(
                    projectID: projectID,
                    ref: ref,
                    query: query,
                    after: nil
                )
            guard
                !Task.isCancelled,
                currentQuery == query
            else {
                return
            }
            results = Self.deduplicated(
                page.results
            )
            nextPageURL = page.nextPageURL
            didSearch = true
        } catch {
            guard
                !Task.isCancelled,
                currentQuery == query
            else {
                return
            }
            self.error = error
            didSearch = true
        }
        if currentQuery == query {
            isSearching = false
        }
    }

    func loadNextPageIfNeeded(
        after result:
            GitLabRepositorySearchResult
    ) async {
        guard
            results.last?.id == result.id,
            let nextPageURL,
            !isSearching,
            !isLoadingNextPage
        else {
            return
        }

        isLoadingNextPage = true
        error = nil
        let query = currentQuery
        do {
            let page = try await loader
                .loadSearchPage(
                    projectID: projectID,
                    ref: ref,
                    query: query,
                    after: nextPageURL
                )
            guard
                !Task.isCancelled,
                currentQuery == query
            else {
                return
            }
            results = Self.deduplicated(
                results + page.results
            )
            self.nextPageURL =
                page.nextPageURL
        } catch {
            guard
                !Task.isCancelled,
                currentQuery == query
            else {
                return
            }
            self.error = error
        }
        if currentQuery == query {
            isLoadingNextPage = false
        }
    }

    func retry() async {
        await search(currentQuery)
    }

    private func clear() {
        currentQuery = ""
        results = []
        nextPageURL = nil
        error = nil
        isSearching = false
        isLoadingNextPage = false
        didSearch = false
    }

    private static func deduplicated(
        _ results:
            [GitLabRepositorySearchResult]
    ) -> [GitLabRepositorySearchResult] {
        var seen: Set<String> = []
        return results.filter {
            seen.insert($0.id).inserted
        }
    }
}

@MainActor
@Observable
final class GitLabRepositoryFileModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(GitLabSourceDocument)
        case failed(
            GitLabRepositorySourceLoadError
        )
    }

    private(set) var state: State = .idle

    private let route:
        GitLabRepositoryFileRoute
    private let loader:
        any GitLabRepositorySourceLoading

    init(
        route: GitLabRepositoryFileRoute,
        loader:
            any GitLabRepositorySourceLoading
    ) {
        self.route = route
        self.loader = loader
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        guard
            case let .failed(error) = state
        else {
            return nil
        }
        return error.authenticationFailure
    }

    func loadIfNeeded() async {
        guard state == .idle else {
            return
        }
        await load()
    }

    func retry() async {
        await load()
    }

    private func load() async {
        state = .loading
        do {
            let document = try await loader
                .loadSource(at: route)
            guard !Task.isCancelled else {
                return
            }
            state = .loaded(document)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error)
        }
    }
}
