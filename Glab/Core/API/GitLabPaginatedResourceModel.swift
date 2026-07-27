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

@MainActor
@Observable
final class GitLabPaginatedResourceModel<Item, Identity>
where
    Item: Sendable,
    Identity: Hashable & Sendable
{
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
    var searchText = ""

    private let loadPage:
        @Sendable (URL?) async throws(GitLabSessionClientError)
            -> GitLabResourcePage<Item>
    private let identity: @Sendable (Item) -> Identity
    private let searchValues: @Sendable (Item) -> [String]

    init(
        loadPage: @escaping @Sendable (URL?) async throws(
            GitLabSessionClientError
        ) -> GitLabResourcePage<Item>,
        identity: @escaping @Sendable (Item) -> Identity,
        searchValues: @escaping @Sendable (Item) -> [String]
    ) {
        self.loadPage = loadPage
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
        await replaceItems(isInitial: true)
    }

    func refresh() async {
        await replaceItems(isInitial: false)
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

    private func replaceItems(isInitial: Bool) async {
        guard
            !isLoadingInitial,
            !isRefreshing,
            !isLoadingNextPage
        else {
            return
        }

        if isInitial {
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
            let page = try await loadPage(nil)
            guard !Task.isCancelled else {
                return
            }

            items = appending(page.items, to: [])
            nextPageURL = page.nextPageURL
            totalItemCount = page.totalCount
            hasLoaded = true
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                return
            }

            loadError = error
            didFailRefresh = !isInitial
            hasLoaded = true
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
                return
            }

            loadError = error
            didFailNextPage = true
        }
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
