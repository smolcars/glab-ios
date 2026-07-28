import Foundation
import Testing
@testable import Glab

@Suite("GitLab discussions model")
struct GitLabDiscussionsModelTests {
    private let resource: GitLabDiscussionResource =
        .issue(
            GitLabIssueRoute(
                projectID: 42,
                issueIID: 7
            )
        )

    @Test("Retains a stale cached first page when revalidation fails")
    @MainActor
    func retainsStaleCacheAfterFailure() async {
        let cached = makeTestDiscussion(
            id: "cached"
        )
        let failure = GitLabSessionClientError.api(
            .connectivity(.notConnectedToInternet)
        )
        let loader = StaleFailingDiscussionLoader(
            cached: cached,
            failure: failure
        )
        let model = GitLabDiscussionsModel(
            resource: resource,
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(model.discussions == [cached])
        #expect(model.didFailRefresh)
        #expect(model.loadError == failure)
        #expect(
            model.firstPageSource
                == .cache(.stale)
        )
        #expect(model.hasLoaded)
    }

    @Test("Loads next pages and suppresses duplicate discussions")
    @MainActor
    func paginatesWithoutDuplicates() async {
        let first = makeTestDiscussion(
            id: "first"
        )
        let second = makeTestDiscussion(
            id: "second",
            notes: [
                makeTestDiscussionNote(
                    id: 201
                ),
                makeTestDiscussionNote(
                    id: 202
                ),
            ]
        )
        let loader = PagingDiscussionLoader(
            first: first,
            second: second
        )
        let model = GitLabDiscussionsModel(
            resource: resource,
            loader: loader
        )

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(
            after: first
        )

        #expect(
            model.discussions.map(\.id)
                == ["first", "second"]
        )
        #expect(
            model.discussions[1].notes.map(\.id)
                == [201, 202]
        )
        #expect(model.nextPageURL == nil)
        #expect(await loader.requestedNextPage)
    }

    @Test("Retains loaded discussions after next-page failure")
    @MainActor
    func retainsContentAfterPaginationFailure()
        async
    {
        let first = makeTestDiscussion()
        let failure = GitLabSessionClientError.api(
            .server(statusCode: 503)
        )
        let loader =
            FailingNextPageDiscussionLoader(
                first: first,
                failure: failure
            )
        let model = GitLabDiscussionsModel(
            resource: resource,
            loader: loader
        )

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(
            after: first
        )

        #expect(model.discussions == [first])
        #expect(model.didFailNextPage)
        #expect(model.loadError == failure)
    }

    @Test("Cancellation restores visible discussion state")
    @MainActor
    func cancellationRestoresState() async {
        let first = makeTestDiscussion()
        let loader =
            GatedRefreshDiscussionLoader(
                first: first
            )
        let model = GitLabDiscussionsModel(
            resource: resource,
            loader: loader
        )
        await model.loadIfNeeded()

        let refresh = Task {
            await model.refresh()
        }
        await loader.waitUntilRefreshStarts()
        refresh.cancel()
        await loader.releaseRefresh()
        await refresh.value

        #expect(model.discussions == [first])
        #expect(!model.didFailRefresh)
        #expect(model.loadError == nil)
        #expect(!model.isRefreshing)
    }

    @Test("Exposes discussion authentication failures")
    @MainActor
    func exposesAuthenticationFailure() async {
        let failure = GitLabSessionClientError.api(
            .unauthenticated
        )
        let model = GitLabDiscussionsModel(
            resource: resource,
            loader:
                AlwaysFailingDiscussionLoader(
                    failure: failure
                )
        )

        await model.loadIfNeeded()

        #expect(model.discussions.isEmpty)
        #expect(
            model.authenticationFailure
                == failure
        )
    }
}

private actor StaleFailingDiscussionLoader:
    GitLabDiscussionLoading
{
    let cached: GitLabDiscussion
    let failure: GitLabSessionClientError

    init(
        cached: GitLabDiscussion,
        failure: GitLabSessionClientError
    ) {
        self.cached = cached
        self.failure = failure
    }

    func loadDiscussionsPage(
        for resource: GitLabDiscussionResource,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabDiscussion>
    {
        throw failure
    }

    func loadDiscussionsFirstPage(
        for resource: GitLabDiscussionResource,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabDiscussion
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        await onPage(
            GitLabResourcePageEvent(
                page: GitLabResourcePage(
                    items: [cached],
                    nextPageURL: nil,
                    totalCount: 1
                ),
                source: .cache(.stale),
                cacheStoredAt: Date(
                    timeIntervalSince1970: 500
                )
            )
        )
        throw failure
    }
}

private actor PagingDiscussionLoader:
    GitLabDiscussionLoading
{
    let first: GitLabDiscussion
    let second: GitLabDiscussion
    private(set) var requestedNextPage = false

    init(
        first: GitLabDiscussion,
        second: GitLabDiscussion
    ) {
        self.first = first
        self.second = second
    }

    func loadDiscussionsPage(
        for resource: GitLabDiscussionResource,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabDiscussion>
    {
        if nextPageURL == nil {
            return GitLabResourcePage(
                items: [first],
                nextPageURL: pageTwo
            )
        }

        requestedNextPage = true
        return GitLabResourcePage(
            items: [first, second],
            nextPageURL: nil
        )
    }

    private var pageTwo: URL {
        URL(
            string:
                "https://gitlab.example.com/api/v4/"
                + "projects/42/issues/7/discussions"
                + "?page=2"
        )!
    }
}

private actor FailingNextPageDiscussionLoader:
    GitLabDiscussionLoading
{
    let first: GitLabDiscussion
    let failure: GitLabSessionClientError

    init(
        first: GitLabDiscussion,
        failure: GitLabSessionClientError
    ) {
        self.first = first
        self.failure = failure
    }

    func loadDiscussionsPage(
        for resource: GitLabDiscussionResource,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabDiscussion>
    {
        guard nextPageURL == nil else {
            throw failure
        }
        return GitLabResourcePage(
            items: [first],
            nextPageURL: URL(
                string:
                    "https://gitlab.example.com/"
                    + "api/v4/discussions?page=2"
            )
        )
    }
}

private actor GatedRefreshDiscussionLoader:
    GitLabDiscussionLoading
{
    let first: GitLabDiscussion
    private var didLoad = false
    private var refreshContinuation:
        CheckedContinuation<Void, Never>?
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var refreshStarted = false

    init(first: GitLabDiscussion) {
        self.first = first
    }

    func loadDiscussionsPage(
        for resource: GitLabDiscussionResource,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabDiscussion>
    {
        if !didLoad {
            didLoad = true
            return GitLabResourcePage(
                items: [first],
                nextPageURL: nil
            )
        }

        refreshStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach {
            $0.resume()
        }
        await withCheckedContinuation {
            refreshContinuation = $0
        }
        guard !Task.isCancelled else {
            throw .api(.cancelled)
        }
        return GitLabResourcePage(
            items: [],
            nextPageURL: nil
        )
    }

    func waitUntilRefreshStarts() async {
        guard !refreshStarted else {
            return
        }
        await withCheckedContinuation {
            startWaiters.append($0)
        }
    }

    func releaseRefresh() {
        refreshContinuation?.resume()
        refreshContinuation = nil
    }
}

private actor AlwaysFailingDiscussionLoader:
    GitLabDiscussionLoading
{
    let failure: GitLabSessionClientError

    init(failure: GitLabSessionClientError) {
        self.failure = failure
    }

    func loadDiscussionsPage(
        for resource: GitLabDiscussionResource,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabDiscussion>
    {
        throw failure
    }
}
