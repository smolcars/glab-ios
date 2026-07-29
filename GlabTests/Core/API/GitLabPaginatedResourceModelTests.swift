import Foundation
import Testing
@testable import Glab

@Suite("GitLab paginated resource model")
struct GitLabPaginatedResourceModelTests {
    @Test("Publishes a cached first page before revalidation completes")
    @MainActor
    func publishesCachedFirstPageImmediately() async {
        let loader = GatedFirstPageLoader(
            outcome: .success(
                GitLabResourcePage(
                    items: [9],
                    nextPageURL: nil,
                    totalCount: 1
                )
            )
        )
        let model = GitLabPaginatedResourceModel<Int, Int>(
            loadPage: {
                (_: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                throw .api(.invalidResponse)
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @Sendable (
                            GitLabResourcePageEvent<Int>
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader.load(
                    refreshBehavior: refreshBehavior,
                    onPage: onPage
                )
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )

        let load = Task {
            await model.loadIfNeeded()
        }
        await loader.waitUntilRevalidating()

        #expect(model.items == [7])
        #expect(!model.isLoadingInitial)
        #expect(model.isRefreshing)
        #expect(
            model.firstPageSource == .cache(.stale)
        )
        #expect(
            model.firstPageCacheStoredAt
                == GatedFirstPageLoader.cacheStoredAt
        )

        await loader.release()
        await load.value

        #expect(model.items == [9])
        #expect(!model.isRefreshing)
        #expect(model.firstPageSource == .network)
        #expect(await loader.refreshBehaviors == [.ifStale])
    }

    @Test("Keeps a cached first page when revalidation fails")
    @MainActor
    func preservesCachedFirstPageAfterFailure() async {
        let failure = GitLabSessionClientError.api(
            .server(statusCode: 500)
        )
        let loader = GatedFirstPageLoader(
            outcome: .failure(failure)
        )
        let model = GitLabPaginatedResourceModel<Int, Int>(
            loadPage: {
                (_: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                throw .api(.invalidResponse)
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @Sendable (
                            GitLabResourcePageEvent<Int>
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader.load(
                    refreshBehavior: refreshBehavior,
                    onPage: onPage
                )
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )

        let load = Task {
            await model.loadIfNeeded()
        }
        await loader.waitUntilRevalidating()
        await loader.release()
        await load.value

        #expect(model.items == [7])
        #expect(model.didFailRefresh)
        #expect(model.loadError == failure)
        #expect(model.firstPageSource == .cache(.stale))
    }

    @Test("Refresh always contacts GitLab after an empty first page")
    @MainActor
    func refreshesEmptyFirstPageFromNetwork() async {
        let loader = EmptyFirstPageLoader()
        let model = GitLabPaginatedResourceModel<Int, Int>(
            loadPage: {
                (_: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                throw .api(.invalidResponse)
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @Sendable (
                            GitLabResourcePageEvent<Int>
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                await loader.load(
                    refreshBehavior: refreshBehavior,
                    onPage: onPage
                )
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )

        await model.loadIfNeeded()
        await model.refresh()

        #expect(model.items.isEmpty)
        #expect(model.hasLoaded)
        #expect(
            await loader.refreshBehaviors
                == [.ifStale, .always]
        )
    }

    @Test(
        "Preserves loaded content across recovery categories",
        arguments: [
            GitLabSessionClientError.api(
                .connectivity(.notConnectedToInternet)
            ),
            GitLabSessionClientError.api(
                .connectivity(.timedOut)
            ),
            GitLabSessionClientError.api(
                .server(statusCode: 503)
            ),
            GitLabSessionClientError.api(.forbidden),
            GitLabSessionClientError.api(.unauthenticated),
            GitLabSessionClientError.api(
                .rateLimited(retryAfterSeconds: 30)
            ),
            GitLabSessionClientError.refresh(
                .token(.invalidGrant)
            ),
        ]
    )
    @MainActor
    func preservesContent(
        error: GitLabSessionClientError
    ) async {
        let loader = FailingRefreshLoader(error: error)
        let model = GitLabPaginatedResourceModel<Int, Int>(
            loadPage: {
                (pageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                try await loader.load(pageURL)
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )

        await model.loadIfNeeded()
        await model.refresh()

        #expect(model.items == [7])
        #expect(model.loadError == error)
        #expect(model.didFailRefresh)
        #expect(model.hasLoaded)
        #expect(model.reliableItemCount == nil)
    }

    @Test("Shows loading while retrying an empty failed resource")
    @MainActor
    func showsLoadingDuringEmptyRetry() async {
        let loader = EmptyRetryLoader()
        let model = GitLabPaginatedResourceModel<Int, Int>(
            loadPage: {
                (pageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                try await loader.load(pageURL)
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )

        await model.loadIfNeeded()

        let retry = Task {
            await model.refresh()
        }
        await loader.waitUntilRetryStarts()

        #expect(model.isLoadingInitial)
        #expect(!model.isRefreshing)

        await loader.finishRetry()
        await retry.value
    }

    @Test("Loads every remaining trusted page")
    @MainActor
    func loadsAllRemainingPages() async {
        let loader = AllPagesLoader()
        let model = GitLabPaginatedResourceModel<
            Int,
            Int
        >(
            loadPage: {
                (
                    pageURL: URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                try await loader.load(pageURL)
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )

        await model.loadIfNeeded()
        let startingRevision =
            model.contentRevision
        await model.loadAllRemainingPages()

        #expect(model.items == [1, 2, 3])
        #expect(model.nextPageURL == nil)
        #expect(!model.didFailNextPage)
        #expect(
            model.contentRevision
                == startingRevision + 2
        )
        #expect(await loader.requestCount == 3)
    }

    @Test("Waits for an overlapping first page before loading the rest")
    @MainActor
    func joinsInitialLoadBeforeLoadingAllPages() async {
        let loader = GatedInitialAllPagesLoader()
        let model = GitLabPaginatedResourceModel<
            Int,
            Int
        >(
            loadPage: {
                (
                    pageURL: URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                await loader.load(pageURL)
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )

        let initialLoad = Task {
            await model.loadIfNeeded()
        }
        await loader.waitUntilInitialPageStarts()

        let remainingLoad = Task {
            await model.loadAllRemainingPages()
        }
        await loader.releaseInitialPage()
        await initialLoad.value
        await remainingLoad.value

        #expect(model.items == [1, 2])
        #expect(model.nextPageURL == nil)
        #expect(await loader.requestCount == 2)
    }

    @Test("Concurrent initial callers wait for one request")
    @MainActor
    func joinsConcurrentInitialLoad() async {
        let loader = CancellableInitialPageLoader()
        let model = GitLabPaginatedResourceModel<
            Int,
            Int
        >(
            loadPage: {
                (
                    pageURL: URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                try await loader.load(pageURL)
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )
        let secondFinished =
            MainActorCompletionBox()

        let firstLoad = Task {
            await model.loadIfNeeded()
        }
        await loader.waitUntilInitialPageStarts()

        let secondLoad = Task {
            await model.loadIfNeeded()
            secondFinished.didFinish = true
        }
        await Task.yield()

        #expect(!secondFinished.didFinish)
        #expect(await loader.requestCount == 1)

        await loader.releaseInitialPage()
        await firstLoad.value
        await secondLoad.value

        #expect(secondFinished.didFinish)
        #expect(model.items == [1])
        #expect(model.hasLoaded)
        #expect(await loader.requestCount == 1)
    }

    @Test("Concurrent initial caller retries after owner cancellation")
    @MainActor
    func retriesCancelledInitialLoad() async {
        let loader = CancellableInitialPageLoader()
        let model = GitLabPaginatedResourceModel<
            Int,
            Int
        >(
            loadPage: {
                (
                    pageURL: URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                try await loader.load(pageURL)
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )

        let firstLoad = Task {
            await model.loadIfNeeded()
        }
        await loader.waitUntilInitialPageStarts()

        let replacementLoad = Task {
            await model.loadIfNeeded()
        }
        await Task.yield()
        firstLoad.cancel()

        await firstLoad.value
        await replacementLoad.value

        #expect(model.items == [1])
        #expect(model.hasLoaded)
        #expect(!model.isLoadingInitial)
        #expect(await loader.requestCount == 2)
    }

    @Test("Cancellation while waiting for the first page skips later pages")
    @MainActor
    func cancelsWhileWaitingForInitialPage() async {
        let loader = GatedInitialAllPagesLoader()
        let model = GitLabPaginatedResourceModel<
            Int,
            Int
        >(
            loadPage: {
                (
                    pageURL: URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                await loader.load(pageURL)
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )

        let initialLoad = Task {
            await model.loadIfNeeded()
        }
        await loader.waitUntilInitialPageStarts()

        let remainingLoad = Task {
            await model.loadAllRemainingPages()
        }
        remainingLoad.cancel()
        await loader.releaseInitialPage()
        await initialLoad.value
        await remainingLoad.value

        #expect(model.items == [1])
        #expect(
            model.nextPageURL
                == URL(
                    string:
                        "https://gitlab.example.com/page-2"
                )
        )
        #expect(await loader.requestCount == 1)
    }

    @Test("Stops and reports a repeated next-page URL")
    @MainActor
    func rejectsRepeatedNextPageURL() async {
        let loader =
            RepeatingNextPageLoader()
        let model = GitLabPaginatedResourceModel<
            Int,
            Int
        >(
            loadPage: {
                (
                    pageURL: URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                await loader.load(pageURL)
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )

        await model.loadIfNeeded()
        await model.loadAllRemainingPages()

        #expect(model.items == [1, 2])
        #expect(model.didFailNextPage)
        #expect(
            model.loadError
                == GitLabSessionClientError
                .api(.invalidResponse)
        )
        #expect(await loader.requestCount == 2)
    }

    @Test("Opt-in refresh refollows shifted pages and removes stale tail")
    @MainActor
    func reconcilesRetainedTailWhenRefreshingFirstPage()
        async
    {
        let loader =
            RetainedTailRefreshLoader()
        let model = GitLabPaginatedResourceModel<
            Int,
            Int
        >(
            loadPage: {
                await loader.load($0)
            },
            firstPageRefreshMode:
                .retainLoadedTail,
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(
            after: 2
        )

        await model.refresh()

        #expect(model.items == [5, 1, 2, 3, 4])
        #expect(
            model.nextPageURL
                == RetainedTailRefreshLoader
                .pageTwoURL
        )
        #expect(model.totalItemCount == 5)
        #expect(!model.didFailRefresh)
        #expect(await loader.requestCount == 3)

        await model.loadAllRemainingPages()

        #expect(model.items == [5, 1, 2, 3])
        #expect(model.nextPageURL == nil)
        #expect(await loader.requestCount == 4)
    }

    @Test("Cancellation keeps already loaded pages")
    @MainActor
    func cancelsLoadAll() async {
        let loader = GatedAllPagesLoader()
        let model = GitLabPaginatedResourceModel<
            Int,
            Int
        >(
            loadPage: {
                (
                    pageURL: URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<Int> in
                await loader.load(pageURL)
            },
            identity: { $0 },
            searchValues: { ["\($0)"] }
        )
        await model.loadIfNeeded()

        let loading = Task {
            await model
                .loadAllRemainingPages()
        }
        await loader.waitUntilNextPageStarts()
        loading.cancel()
        await loader.release()
        await loading.value

        #expect(model.items == [1])
        #expect(!model.didFailNextPage)
        #expect(model.loadError == nil)
        #expect(!model.isLoadingNextPage)
    }

    @Test("Removing a reconciled item updates count and revision once")
    @MainActor
    func removesItemIfPresent() async {
        let model =
            GitLabPaginatedResourceModel<
                Int,
                Int
            >(
                loadPage: { _ in
                    GitLabResourcePage(
                        items: [1, 2],
                        nextPageURL: nil,
                        totalCount: 2
                    )
                },
                identity: { $0 },
                searchValues: {
                    ["\($0)"]
                }
            )
        await model.loadIfNeeded()
        let revision =
            model.contentRevision

        let removed =
            model.removeItemIfPresent(1)
        let repeated =
            model.removeItemIfPresent(1)

        #expect(removed)
        #expect(!repeated)
        #expect(model.items == [2])
        #expect(model.totalItemCount == 1)
        #expect(
            model.contentRevision
                == revision + 1
        )
    }
}

@MainActor
private final class MainActorCompletionBox {
    var didFinish = false
}

private actor CancellableInitialPageLoader {
    private var didStartInitialPage = false
    private var initialStartWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var initialContinuation:
        CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    func load(
        _ pageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<Int>
    {
        guard pageURL == nil else {
            throw .api(.invalidResponse)
        }

        requestCount += 1
        if requestCount == 1 {
            didStartInitialPage = true
            let waiters = initialStartWaiters
            initialStartWaiters.removeAll()
            waiters.forEach { $0.resume() }

            do {
                try await withTaskCancellationHandler {
                    await withCheckedContinuation {
                        initialContinuation = $0
                    }
                    try Task.checkCancellation()
                } onCancel: {
                    Task {
                        await self.releaseInitialPage()
                    }
                }
            } catch {
                throw .api(.cancelled)
            }
        }

        return GitLabResourcePage(
            items: [1],
            nextPageURL: nil,
            totalCount: 1
        )
    }

    func waitUntilInitialPageStarts() async {
        guard !didStartInitialPage else {
            return
        }
        await withCheckedContinuation {
            initialStartWaiters.append($0)
        }
    }

    func releaseInitialPage() {
        initialContinuation?.resume()
        initialContinuation = nil
    }
}

private actor AllPagesLoader {
    private(set) var requestCount = 0

    func load(
        _ pageURL: URL?
    ) throws(GitLabSessionClientError)
        -> GitLabResourcePage<Int>
    {
        requestCount += 1
        switch pageURL?.lastPathComponent {
        case nil:
            return page(
                item: 1,
                next: "page-2"
            )
        case "page-2":
            return page(
                item: 2,
                next: "page-3"
            )
        case "page-3":
            return page(
                item: 3,
                next: nil
            )
        default:
            throw .api(.invalidResponse)
        }
    }

    private func page(
        item: Int,
        next: String?
    ) -> GitLabResourcePage<Int> {
        GitLabResourcePage(
            items: [item],
            nextPageURL: next.flatMap {
                URL(
                    string:
                        "https://gitlab.example.com/\($0)"
                )
            },
            totalCount: 3
        )
    }
}

private actor GatedInitialAllPagesLoader {
    private var didStartInitialPage = false
    private var initialStartWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var initialContinuation:
        CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    func load(
        _ pageURL: URL?
    ) async -> GitLabResourcePage<Int> {
        requestCount += 1
        guard pageURL == nil else {
            return GitLabResourcePage(
                items: [2],
                nextPageURL: nil,
                totalCount: 2
            )
        }

        didStartInitialPage = true
        let waiters = initialStartWaiters
        initialStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation {
            initialContinuation = $0
        }
        return GitLabResourcePage(
            items: [1],
            nextPageURL: URL(
                string:
                    "https://gitlab.example.com/page-2"
            ),
            totalCount: 2
        )
    }

    func waitUntilInitialPageStarts() async {
        guard !didStartInitialPage else {
            return
        }
        await withCheckedContinuation {
            initialStartWaiters.append($0)
        }
    }

    func releaseInitialPage() {
        initialContinuation?.resume()
        initialContinuation = nil
    }
}

private actor RepeatingNextPageLoader {
    private(set) var requestCount = 0
    private let repeatedURL = URL(
        string:
            "https://gitlab.example.com/page-2"
    )

    func load(
        _ pageURL: URL?
    ) -> GitLabResourcePage<Int> {
        requestCount += 1
        return GitLabResourcePage(
            items: [pageURL == nil ? 1 : 2],
            nextPageURL: repeatedURL,
            totalCount: 3
        )
    }
}

private actor RetainedTailRefreshLoader {
    private(set) var requestCount = 0
    private var firstPageRequestCount = 0
    static let pageTwoURL = URL(
        string:
            "https://gitlab.example.com/items?page=2"
    )

    func load(
        _ pageURL: URL?
    ) -> GitLabResourcePage<Int> {
        requestCount += 1

        if pageURL == nil {
            firstPageRequestCount += 1
            if firstPageRequestCount == 1 {
                return GitLabResourcePage(
                    items: [1, 2],
                    nextPageURL: Self.pageTwoURL,
                    totalCount: 4
                )
            }
            return GitLabResourcePage(
                items: [5, 1],
                nextPageURL: Self.pageTwoURL,
                totalCount: 5
            )
        }

        return GitLabResourcePage(
            items:
                firstPageRequestCount == 1
                ? [3, 4]
                : [2, 3],
            nextPageURL: nil,
            totalCount: 4
        )
    }
}

private actor GatedAllPagesLoader {
    private var didStartNextPage = false
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var continuation:
        CheckedContinuation<Void, Never>?

    func load(
        _ pageURL: URL?
    ) async -> GitLabResourcePage<Int> {
        guard pageURL != nil else {
            return GitLabResourcePage(
                items: [1],
                nextPageURL: URL(
                    string:
                        "https://gitlab.example.com/page-2"
                ),
                totalCount: 2
            )
        }

        didStartNextPage = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation {
            continuation = $0
        }
        return GitLabResourcePage(
            items: [2],
            nextPageURL: nil,
            totalCount: 2
        )
    }

    func waitUntilNextPageStarts() async {
        guard !didStartNextPage else {
            return
        }
        await withCheckedContinuation {
            startWaiters.append($0)
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor EmptyFirstPageLoader {
    private(set) var refreshBehaviors:
        [GitLabCacheRefreshBehavior] = []

    func load(
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @Sendable (
                GitLabResourcePageEvent<Int>
            ) async -> Void
    ) async {
        refreshBehaviors.append(refreshBehavior)
        await onPage(
            GitLabResourcePageEvent(
                page: GitLabResourcePage(
                    items: [],
                    nextPageURL: nil,
                    totalCount: 0
                ),
                source: .network
            )
        )
    }
}

private actor GatedFirstPageLoader {
    let outcome:
        Result<GitLabResourcePage<Int>, GitLabSessionClientError>
    private var continuation:
        CheckedContinuation<Void, Never>?
    private var revalidationWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var isRevalidating = false
    private(set) var refreshBehaviors:
        [GitLabCacheRefreshBehavior] = []
    static let cacheStoredAt = Date(
        timeIntervalSince1970: 10_000
    )

    init(
        outcome:
            Result<GitLabResourcePage<Int>, GitLabSessionClientError>
    ) {
        self.outcome = outcome
    }

    func load(
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @Sendable (
                GitLabResourcePageEvent<Int>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        refreshBehaviors.append(refreshBehavior)
        await onPage(
            GitLabResourcePageEvent(
                page: GitLabResourcePage(
                    items: [7],
                    nextPageURL: URL(
                        string:
                            "https://gitlab.example.com/items?page=2"
                    ),
                    totalCount: 2
                ),
                source: .cache(.stale),
                cacheStoredAt: Self.cacheStoredAt
            )
        )

        isRevalidating = true
        let waiters = revalidationWaiters
        revalidationWaiters.removeAll()
        waiters.forEach {
            $0.resume()
        }
        await withCheckedContinuation {
            continuation = $0
        }

        switch outcome {
        case let .success(page):
            await onPage(
                GitLabResourcePageEvent(
                    page: page,
                    source: .network
                )
            )
        case let .failure(error):
            throw error
        }
    }

    func waitUntilRevalidating() async {
        guard !isRevalidating else {
            return
        }

        await withCheckedContinuation {
            revalidationWaiters.append($0)
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor FailingRefreshLoader {
    private let error: GitLabSessionClientError
    private var requestCount = 0

    init(error: GitLabSessionClientError) {
        self.error = error
    }

    func load(
        _ pageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<Int>
    {
        requestCount += 1

        if requestCount == 1 {
            return GitLabResourcePage(
                items: [7],
                nextPageURL: nil,
                totalCount: 1
            )
        }

        throw error
    }
}

private actor EmptyRetryLoader {
    private var requestCount = 0
    private var retryContinuation:
        CheckedContinuation<Void, Never>?
    private var retryStartedContinuation:
        CheckedContinuation<Void, Never>?

    func load(
        _ pageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<Int>
    {
        requestCount += 1

        if requestCount == 1 {
            throw .api(.server(statusCode: 503))
        }

        await withCheckedContinuation {
            retryContinuation = $0
            retryStartedContinuation?.resume()
            retryStartedContinuation = nil
        }

        return GitLabResourcePage(
            items: [],
            nextPageURL: nil,
            totalCount: 0
        )
    }

    func waitUntilRetryStarts() async {
        guard retryContinuation == nil else {
            return
        }

        await withCheckedContinuation {
            retryStartedContinuation = $0
        }
    }

    func finishRetry() {
        retryContinuation?.resume()
        retryContinuation = nil
    }
}
