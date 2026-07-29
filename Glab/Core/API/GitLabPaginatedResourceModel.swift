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

nonisolated enum GitLabFirstPageRefreshMode:
    Equatable,
    Sendable
{
    case replaceAll
    case retainLoadedTail
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

    private var reconciledTailItems: [Item] = []
    private var retainedServerTailItems: [Item] = []
    private var loadedNextPageURLs: Set<URL> = []
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
    private let firstPageRefreshMode:
        GitLabFirstPageRefreshMode
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
        firstPageRefreshMode:
            GitLabFirstPageRefreshMode = .replaceAll,
        identity: @escaping @Sendable (Item) -> Identity,
        searchValues: @escaping @Sendable (Item) -> [String]
    ) {
        self.loadPage = loadPage
        self.loadFirstPage = loadFirstPage
        self.firstPageRefreshMode =
            firstPageRefreshMode
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
        while
            !hasLoaded,
            !Task.isCancelled
        {
            if
                isLoadingInitial
                    || isRefreshing
            {
                await waitForOverlappingInitialLoad()
            } else {
                await replaceItems(
                    showsInitialLoading: true,
                    refreshBehavior: .ifStale
                )
                return
            }
        }
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

    func loadAllRemainingPages() async {
        if
            isLoadingInitial
                || isRefreshing
                || isLoadingNextPage
        {
            for await loadState in Observations({
                (
                    self.isLoadingInitial,
                    self.isRefreshing,
                    self.isLoadingNextPage
                )
            }) {
                guard !Task.isCancelled else {
                    return
                }
                if
                    !loadState.0,
                    !loadState.1,
                    !loadState.2
                {
                    break
                }
            }
        }

        guard
            !Task.isCancelled,
            !isLoadingInitial,
            !isRefreshing,
            !isLoadingNextPage,
            !didFailRefresh
        else {
            return
        }

        while
            nextPageURL != nil,
            !Task.isCancelled,
            !didFailNextPage
        {
            await loadNextPage()
        }
    }

    @discardableResult
    func reconcileItem(
        _ item: Item,
        countAdjustmentIfInserted: Int = 0,
        keepsAtEndUntilLoaded: Bool = false
    ) -> Bool {
        let itemIdentity = identity(item)
        if
            let index = items.firstIndex(
                where: {
                    identity($0)
                        == itemIdentity
                }
            )
        {
            items[index] = item
            if
                let tailIndex =
                    reconciledTailItems.firstIndex(
                        where: {
                            identity($0)
                                == itemIdentity
                        }
                    )
            {
                reconciledTailItems[tailIndex] =
                    item
            }
            if
                let tailIndex =
                    retainedServerTailItems
                    .firstIndex(
                        where: {
                            identity($0)
                                == itemIdentity
                        }
                    )
            {
                retainedServerTailItems[
                    tailIndex
                ] = item
            }
            contentRevision += 1
            return false
        }

        items.append(item)
        if keepsAtEndUntilLoaded {
            reconciledTailItems.append(item)
        }
        if let totalItemCount {
            self.totalItemCount = max(
                0,
                totalItemCount
                    + countAdjustmentIfInserted
            )
        }
        contentRevision += 1
        return true
    }

    @discardableResult
    func reconcileItemIfPresent(
        _ item: Item
    ) -> Bool {
        guard
            hasLoaded,
            items.contains(
                where: {
                    identity($0) == identity(item)
                }
            )
        else {
            return false
        }

        _ = reconcileItem(item)
        return true
    }

    @discardableResult
    func removeItemIfPresent(
        _ item: Item
    ) -> Bool {
        let itemIdentity = identity(item)
        guard
            let index = items.firstIndex(
                where: {
                    identity($0)
                        == itemIdentity
                }
            )
        else {
            return false
        }

        items.remove(at: index)
        reconciledTailItems.removeAll {
            identity($0) == itemIdentity
        }
        retainedServerTailItems.removeAll {
            identity($0) == itemIdentity
        }
        if let totalItemCount {
            self.totalItemCount = max(
                0,
                totalItemCount - 1
            )
        }
        contentRevision += 1
        return true
    }

    private func waitForOverlappingInitialLoad()
        async
    {
        guard
            !hasLoaded,
            isLoadingInitial || isRefreshing
        else {
            return
        }

        for await state in Observations({
            (
                self.hasLoaded,
                self.isLoadingInitial,
                self.isRefreshing
            )
        }) {
            guard !Task.isCancelled else {
                return
            }
            if
                state.0
                    || (!state.1 && !state.2)
            {
                return
            }
        }
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
        let refreshedIdentities =
            Set(event.page.items.map(identity))
        let reconciledIdentities =
            Set(
                reconciledTailItems.map(identity)
            )
        let retainedTail =
            firstPageRefreshMode
                == .retainLoadedTail
                && hasLoaded
                && event.page.nextPageURL != nil
            ? items.filter {
                !refreshedIdentities.contains(
                    identity($0)
                )
                    && !reconciledIdentities
                    .contains(identity($0))
            }
            : []
        retainedServerTailItems =
            retainedTail
        loadedNextPageURLs.removeAll()
        items = appendingServerItems(
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
        guard
            loadedNextPageURLs
                .insert(nextPageURL)
                .inserted
        else {
            loadError = .api(.invalidResponse)
            didFailNextPage = true
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
                loadedNextPageURLs.remove(
                    nextPageURL
                )
                restoreFailureState(previousFailureState)
                return
            }

            items = appendingServerItems(
                page.items,
                to: items
            )
            self.nextPageURL = page.nextPageURL
            if page.nextPageURL == nil {
                discardRetainedServerTail()
            }
            totalItemCount =
                page.totalCount ?? totalItemCount
            contentRevision += 1
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                loadedNextPageURLs.remove(
                    nextPageURL
                )
                restoreFailureState(previousFailureState)
                return
            }

            loadedNextPageURLs.remove(
                nextPageURL
            )
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

    private func appendingServerItems(
        _ newItems: [Item],
        to existingItems: [Item]
    ) -> [Item] {
        let previousTailIdentities =
            Set(reconciledTailItems.map(identity))
        let previousServerTailIdentities =
            Set(
                retainedServerTailItems
                    .map(identity)
            )
        let loadedIdentities =
            Set(newItems.map(identity))

        reconciledTailItems.removeAll {
            loadedIdentities.contains(identity($0))
        }
        retainedServerTailItems.removeAll {
            loadedIdentities.contains(identity($0))
        }

        let existingWithoutTail =
            existingItems.filter {
                !previousTailIdentities.contains(
                    identity($0)
                )
                    && !previousServerTailIdentities
                    .contains(identity($0))
            }
        let loadedItems = appending(
            newItems,
            to: existingWithoutTail
        )
        let loadedWithServerTail =
            appending(
                retainedServerTailItems,
                to: loadedItems
            )
        return appending(
            reconciledTailItems,
            to: loadedWithServerTail
        )
    }

    private func discardRetainedServerTail() {
        let retainedIdentities =
            Set(
                retainedServerTailItems
                    .map(identity)
            )
        items.removeAll {
            retainedIdentities.contains(
                identity($0)
            )
        }
        retainedServerTailItems.removeAll()
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
