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

    @Test("Reconciles created discussions by real server identity")
    @MainActor
    func reconcilesCreatedDiscussion() async {
        let first = makeTestDiscussion(
            id: "first"
        )
        let loader =
            StaticDiscussionLoader(
                discussions: [first],
                totalCount: 1
            )
        let model = GitLabDiscussionsModel(
            resource: resource,
            loader: loader
        )
        await model.loadIfNeeded()
        let startingRevision =
            model.contentRevision
        let created = makeTestDiscussion(
            id: "created",
            notes: [
                makeTestDiscussionNote(
                    id: 202,
                    body: "Created"
                ),
            ]
        )

        model.reconcileCreatedDiscussion(
            created
        )

        #expect(
            model.discussions == [
                first,
                created,
            ]
        )
        #expect(model.totalItemCount == 2)
        #expect(
            model.contentRevision
                == startingRevision + 1
        )

        let serverUpdate =
            makeTestDiscussion(
                id: "created",
                notes: [
                    makeTestDiscussionNote(
                        id: 202,
                        body: "Server update"
                    ),
                ]
            )
        model.reconcileCreatedDiscussion(
            serverUpdate
        )

        #expect(
            model.discussions == [
                first,
                serverUpdate,
            ]
        )
        #expect(model.totalItemCount == 2)
    }

    @Test("Keeps a created discussion after subsequently loaded older pages")
    @MainActor
    func keepsCreatedDiscussionAtPaginationTail()
        async
    {
        let first = makeTestDiscussion(
            id: "first"
        )
        let second = makeTestDiscussion(
            id: "second"
        )
        let created = makeTestDiscussion(
            id: "created"
        )
        let model = GitLabDiscussionsModel(
            resource: resource,
            loader:
                PagingDiscussionLoader(
                    first: first,
                    second: second
                )
        )
        await model.loadIfNeeded()
        model.reconcileCreatedDiscussion(
            created
        )

        await model.loadNextPageIfNeeded(
            after: created
        )

        #expect(
            model.discussions.map(\.id)
                == [
                    "first",
                    "second",
                    "created",
                ]
        )
    }

    @Test("Reconciles replies by real note identity")
    @MainActor
    func reconcilesCreatedReply() async {
        let original = makeTestDiscussion(
            id: "thread",
            notes: [
                makeTestDiscussionNote(
                    id: 101,
                    body: "Original"
                ),
            ]
        )
        let model = GitLabDiscussionsModel(
            resource: resource,
            loader:
                StaticDiscussionLoader(
                    discussions: [original]
                )
        )
        await model.loadIfNeeded()
        let reply =
            makeTestDiscussionNote(
                id: 202,
                body: "Reply"
            )

        #expect(
            model.reconcileCreatedReply(
                reply,
                discussionID: "thread"
            )
        )
        #expect(
            model.discussions[0].notes
                .map(\.id)
                == [101, 202]
        )

        let serverUpdate =
            makeTestDiscussionNote(
                id: 202,
                body: "Updated reply"
            )
        #expect(
            model.reconcileCreatedReply(
                serverUpdate,
                discussionID: "thread"
            )
        )
        #expect(
            model.discussions[0].notes
                == [
                    original.notes[0],
                    serverUpdate,
                ]
        )
        #expect(model.totalItemCount == nil)
    }

    @Test("A missing reply target does not invent a discussion")
    @MainActor
    func ignoresMissingReplyTarget() async {
        let original = makeTestDiscussion(
            id: "thread"
        )
        let model = GitLabDiscussionsModel(
            resource: resource,
            loader:
                StaticDiscussionLoader(
                    discussions: [original]
                )
        )
        await model.loadIfNeeded()

        #expect(
            !model.reconcileCreatedReply(
                makeTestDiscussionNote(
                    id: 202
                ),
                discussionID: "missing"
            )
        )
        #expect(
            model.discussions == [original]
        )
    }

    @Test("Reconciles an authoritative discussion without reordering or changing count")
    @MainActor
    func reconcilesAuthoritativeDiscussion()
        async
    {
        let first =
            makeTestDiscussion(
                id: "first"
            )
        let original =
            makeTestDiscussion(
                id: "target"
            )
        let last =
            makeTestDiscussion(
                id: "last"
            )
        let model =
            GitLabDiscussionsModel(
                resource: resource,
                loader:
                    StaticDiscussionLoader(
                        discussions: [
                            first,
                            original,
                            last,
                        ],
                        totalCount: 9
                    )
            )
        await model.loadIfNeeded()
        let startingRevision =
            model.contentRevision
        let authoritative =
            makeTestDiscussion(
                id: "target",
                notes: [
                    makeTestDiscussionNote(
                        resolvable: true,
                        resolved: true
                    ),
                ]
            )

        #expect(
            model
                .reconcileAuthoritativeDiscussion(
                    authoritative
                )
        )
        #expect(
            model.discussions == [
                first,
                authoritative,
                last,
            ]
        )
        #expect(model.totalItemCount == 9)
        #expect(
            model.contentRevision
                == startingRevision + 1
        )
    }

    @Test("Reconciles an authoritative update retained at the pagination tail")
    @MainActor
    func reconcilesAuthoritativeTail()
        async
    {
        let first =
            makeTestDiscussion(
                id: "first"
            )
        let second =
            makeTestDiscussion(
                id: "second"
            )
        let created =
            makeTestDiscussion(
                id: "created"
            )
        let authoritative =
            makeTestDiscussion(
                id: "created",
                notes: [
                    makeTestDiscussionNote(
                        body: "Authoritative"
                    ),
                ]
            )
        let model =
            GitLabDiscussionsModel(
                resource: resource,
                loader:
                    PagingDiscussionLoader(
                        first: first,
                        second: second
                    )
            )
        await model.loadIfNeeded()
        model.reconcileCreatedDiscussion(
            created
        )

        #expect(
            model
                .reconcileAuthoritativeDiscussion(
                    authoritative
                )
        )
        await model.loadNextPageIfNeeded(
            after: authoritative
        )

        #expect(
            model.discussions == [
                first,
                second,
                authoritative,
            ]
        )
    }

    @Test("A missing authoritative identity is not inserted")
    @MainActor
    func ignoresMissingAuthoritativeDiscussion()
        async
    {
        let original =
            makeTestDiscussion(
                id: "original"
            )
        let model =
            GitLabDiscussionsModel(
                resource: resource,
                loader:
                    StaticDiscussionLoader(
                        discussions: [original],
                        totalCount: 4
                    )
            )
        await model.loadIfNeeded()
        let startingRevision =
            model.contentRevision

        #expect(
            !model
                .reconcileAuthoritativeDiscussion(
                    makeTestDiscussion(
                        id: "missing"
                    )
                )
        )
        #expect(
            model.discussions == [original]
        )
        #expect(model.totalItemCount == 4)
        #expect(
            model.contentRevision
                == startingRevision
        )
    }

    @Test("Reconciles composer results through one shared path")
    @MainActor
    func reconcilesComposerResults() async {
        let original = makeTestDiscussion(
            id: "thread"
        )
        let model = GitLabDiscussionsModel(
            resource: resource,
            loader:
                StaticDiscussionLoader(
                    discussions: [original]
                )
        )
        await model.loadIfNeeded()
        let created = makeTestDiscussion(
            id: "created"
        )
        let reply = makeTestDiscussionNote(
            id: 404,
            body: "Shared path reply"
        )

        model.reconcile(
            .discussion(created)
        )
        model.reconcile(
            .reply(
                reply,
                discussionID: "thread"
            )
        )

        #expect(
            model.discussions.map(\.id)
                == ["thread", "created"]
        )
        #expect(
            model.discussions[0].notes.last
                == reply
        )
    }
}

private actor StaticDiscussionLoader:
    GitLabDiscussionLoading
{
    let discussions: [GitLabDiscussion]
    let totalCount: Int?

    init(
        discussions: [GitLabDiscussion],
        totalCount: Int? = nil
    ) {
        self.discussions = discussions
        self.totalCount = totalCount
    }

    func loadDiscussionsPage(
        for resource: GitLabDiscussionResource,
        after nextPageURL: URL?
    ) -> GitLabResourcePage<GitLabDiscussion> {
        GitLabResourcePage(
            items: discussions,
            nextPageURL: nil,
            totalCount: totalCount
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
