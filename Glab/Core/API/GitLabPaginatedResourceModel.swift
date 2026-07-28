import Foundation
import Observation

nonisolated struct GitLabResourcePage<Item>: Sendable
where Item: Sendable {
    let items: [Item]
    let nextPageURL: URL?
    let totalCount: Int?

    init(
        items: [Item],
        nextPageURL: URL?,
        totalCount: Int? = nil
    ) {
        self.items = items
        self.nextPageURL = nextPageURL
        self.totalCount = totalCount
    }
}

nonisolated struct GitLabResourcePageEvent<Item>:
    Sendable
where Item: Sendable {
    let page: GitLabResourcePage<Item>
    let source: GitLabAPIResponseSource
    let cacheStoredAt: Date?

    init(
        page: GitLabResourcePage<Item>,
        source: GitLabAPIResponseSource,
        cacheStoredAt: Date? = nil
    ) {
        self.page = page
        self.source = source
        self.cacheStoredAt = cacheStoredAt
    }

    init(
        apiResponse:
            GitLabAPIResponseEvent<[Item]>
    ) {
        self.init(
            page: GitLabResourcePage(
                items: apiResponse.value,
                nextPageURL:
                    apiResponse.metadata.nextPageURL,
                totalCount:
                    apiResponse.metadata.totalCount
            ),
            source: apiResponse.source,
            cacheStoredAt:
                apiResponse.cacheStoredAt
        )
    }
}

@MainActor
@Observable
final class GitLabPaginatedResourceModel<Item, Identity>
where
    Item: Sendable,
    Identity: Hashable & Sendable
{
    private struct FailureState {
        let loadError: GitLabSessionClientError?
        let didFailRefresh: Bool
        let didFailNextPage: Bool
    }

    private(set) var items: [Item] = []
    private(set) var nextPageURL: URL?
    private(set) var totalItemCount: Int?
    private(set) var loadError: GitLabSessionClientError?
    private(set) var isLoadingInitial = false
    private(set) var isRefreshing = false
    private(set) var isLoadingNextPage = false
    private(set) var didFailRefresh = false
    private(set) var didFailNextPage = false
    private(set) var hasLoaded = false
    private(set) var contentRevision = 0
    private(set) var firstPageSource:
        GitLabAPIResponseSource?
    private(set) var firstPageCacheStoredAt: Date?
    var searchText = ""

    private let loadPage:
        @Sendable (URL?) async throws(GitLabSessionClientError)
            -> GitLabResourcePage<Item>
    private let loadFirstPage:
        (@Sendable (
            GitLabCacheRefreshBehavior,
            @escaping @Sendable (
                GitLabResourcePageEvent<Item>
            ) async -> Void
        ) async throws(GitLabSessionClientError) -> Void)?
    private let identity: @Sendable (Item) -> Identity
    private let searchValues: @Sendable (Item) -> [String]

    init(
        loadPage: @escaping @Sendable (URL?) async throws(
            GitLabSessionClientError
        ) -> GitLabResourcePage<Item>,
        loadFirstPage:
            (@Sendable (
                GitLabCacheRefreshBehavior,
                @escaping @Sendable (
                    GitLabResourcePageEvent<Item>
                ) async -> Void
            ) async throws(GitLabSessionClientError) -> Void)? = nil,
        identity: @escaping @Sendable (Item) -> Identity,
        searchValues: @escaping @Sendable (Item) -> [String]
    ) {
        self.loadPage = loadPage
        self.loadFirstPage = loadFirstPage
        self.identity = identity
        self.searchValues = searchValues
    }

    var displayedItems: [Item] {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            return items
        }

        return items.filter {
            matches($0, query: query)
        }
    }

    var authenticationFailure: GitLabSessionClientError? {
        guard loadError?.requiresReauthentication == true else {
            return nil
        }
        return loadError
    }

    var reliableItemCount: Int? {
        guard
            hasLoaded,
            !didFailRefresh
        else {
            return nil
        }
        if let totalItemCount {
            return totalItemCount
        }
        return nextPageURL == nil ? items.count : nil
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }
        await replaceItems(
            showsInitialLoading: true,
            refreshBehavior: .ifStale
        )
    }

    func refresh() async {
        await replaceItems(
            showsInitialLoading: items.isEmpty,
            refreshBehavior: .always
        )
    }

    func loadNextPageIfNeeded(after item: Item) async {
        guard items.last.map(identity) == identity(item) else {
            return
        }
        await loadNextPage()
    }

    func retryNextPage() async {
        await loadNextPage()
    }

    private func replaceItems(
        showsInitialLoading: Bool,
        refreshBehavior: GitLabCacheRefreshBehavior
    ) async {
        guard
            !isLoadingInitial,
            !isRefreshing,
            !isLoadingNextPage
        else {
            return
        }

        let previousFailureState = failureState
        if showsInitialLoading {
            isLoadingInitial = true
        } else {
            isRefreshing = true
        }
        loadError = nil
        didFailRefresh = false
        didFailNextPage = false

        defer {
            isLoadingInitial = false
            isRefreshing = false
        }

        do {
            if let loadFirstPage {
                try await loadFirstPage(
                    refreshBehavior
                ) { [weak self] event in
                    guard !Task.isCancelled else {
                        return
                    }
                    await self?.applyFirstPage(event)
                }
            } else {
                let page = try await loadPage(nil)
                applyFirstPage(
                    GitLabResourcePageEvent(
                        page: page,
                        source: .network
                    )
                )
            }

            guard !Task.isCancelled else {
                restoreFailureState(previousFailureState)
                return
            }
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                restoreFailureState(previousFailureState)
                return
            }

            let retainedFirstPage = hasLoaded
            loadError = error
            didFailRefresh =
                !showsInitialLoading
                    || retainedFirstPage
            hasLoaded = true
        }
    }

    private func applyFirstPage(
        _ event: GitLabResourcePageEvent<Item>
    ) {
        items = appending(
            event.page.items,
            to: []
        )
        nextPageURL = event.page.nextPageURL
        totalItemCount = event.page.totalCount
        firstPageSource = event.source
        firstPageCacheStoredAt = event.cacheStoredAt
        loadError = nil
        didFailRefresh = false
        didFailNextPage = false
        hasLoaded = true
        contentRevision += 1

        switch event.source {
        case .cache(.stale):
            isLoadingInitial = false
            isRefreshing = true
        case .cache(.fresh), .network:
            isLoadingInitial = false
        case .cache(.expired):
            break
        }
    }

    private func loadNextPage() async {
        guard
            let nextPageURL,
            !isLoadingInitial,
            !isRefreshing,
            !isLoadingNextPage,
            !didFailRefresh
        else {
            return
        }

        let previousFailureState = failureState
        isLoadingNextPage = true
        loadError = nil
        didFailRefresh = false
        didFailNextPage = false

        defer {
            isLoadingNextPage = false
        }

        do {
            let page = try await loadPage(nextPageURL)
            guard !Task.isCancelled else {
                restoreFailureState(previousFailureState)
                return
            }

            items = appending(page.items, to: items)
            self.nextPageURL = page.nextPageURL
            totalItemCount =
                page.totalCount ?? totalItemCount
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                restoreFailureState(previousFailureState)
                return
            }

            loadError = error
            didFailNextPage = true
        }
    }

    private var failureState: FailureState {
        FailureState(
            loadError: loadError,
            didFailRefresh: didFailRefresh,
            didFailNextPage: didFailNextPage
        )
    }

    private func restoreFailureState(_ state: FailureState) {
        loadError = state.loadError
        didFailRefresh = state.didFailRefresh
        didFailNextPage = state.didFailNextPage
    }

    private func appending(
        _ newItems: [Item],
        to existingItems: [Item]
    ) -> [Item] {
        var identities = Set(existingItems.map(identity))
        var result = existingItems

        for item in newItems
        where identities.insert(identity(item)).inserted
        {
            result.append(item)
        }

        return result
    }

    private func matches(
        _ item: Item,
        query: String
    ) -> Bool {
        searchValues(item).contains {
            $0.range(
                of: query,
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                ]
            ) != nil
        }
    }
}
