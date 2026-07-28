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
