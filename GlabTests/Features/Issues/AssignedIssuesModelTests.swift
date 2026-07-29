import Foundation
import Testing
@testable import Glab

@Suite("Assigned issues model")
@MainActor
struct AssignedIssuesModelTests {
    @Test("Loads created issues with an independent scope")
    func loadsCreatedScope() async {
        let issue = makeTestIssue()
        let loader = StubIssueLoader(
            pageResults: [
                .success(
                    GitLabIssuePage(
                        issues: [issue],
                        nextPageURL: nil
                    )
                ),
            ]
        )
        let model = IssuesModel(
            mode: .created,
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(model.issues == [issue])
        #expect(await loader.modes == [.created])
    }

    @Test("Appends pages without duplicate issue routes")
    func appendsPagesWithoutDuplicates() async throws {
        let first = makeTestIssue(
            id: 1,
            iid: 1,
            title: "First"
        )
        let second = makeTestIssue(
            id: 2,
            iid: 2,
            title: "Second"
        )
        let duplicateSecond = makeTestIssue(
            id: 20,
            iid: 2,
            title: "Duplicate second"
        )
        let third = makeTestIssue(
            id: 3,
            iid: 3,
            title: "Third"
        )
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/issues?page=2"
            )
        )
        let loader = StubIssueLoader(
            pageResults: [
                .success(
                    GitLabIssuePage(
                        issues: [first, second],
                        nextPageURL: nextPageURL
                    )
                ),
                .success(
                    GitLabIssuePage(
                        issues: [duplicateSecond, third],
                        nextPageURL: nil
                    )
                ),
            ]
        )
        let model = AssignedIssuesModel(loader: loader)

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(
            after: try #require(model.issues.last)
        )

        #expect(model.issues.map(\.title) == ["First", "Second", "Third"])
        #expect(model.nextPageURL == nil)
        #expect(await loader.pageRequestURLs == [nil, nextPageURL])
    }

    @Test("Loads another page only from the last row")
    func loadsNextPageFromLastRow() async throws {
        let first = makeTestIssue(id: 1, iid: 1)
        let second = makeTestIssue(id: 2, iid: 2)
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/issues?page=2"
            )
        )
        let loader = StubIssueLoader(
            pageResults: [
                .success(
                    GitLabIssuePage(
                        issues: [first, second],
                        nextPageURL: nextPageURL
                    )
                ),
                .success(
                    GitLabIssuePage(
                        issues: [],
                        nextPageURL: nil
                    )
                ),
            ]
        )
        let model = AssignedIssuesModel(loader: loader)

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(after: first)

        #expect(await loader.pageRequestURLs == [nil])
    }

    @Test("Reconciliation removes closed or unassigned issues")
    func removesIneligibleIssue() async {
        let issue = makeTestIssue(
            assignees: [
                makeTestIssueUser(id: 2),
            ]
        )
        let loader = StubIssueLoader(
            pageResults: [
                .success(
                    GitLabIssuePage(
                        issues: [issue],
                        nextPageURL: nil
                    )
                ),
            ]
        )
        let model =
            AssignedIssuesModel(
                loader: loader
            )
        await model.loadIfNeeded()

        let removed =
            model.reconcileAssignedIssue(
                makeTestIssue(
                    state: "closed",
                    assignees: [
                        makeTestIssueUser(
                            id: 2
                        ),
                    ]
                ),
                currentUserID: 2
            )

        #expect(removed)
        #expect(model.issues.isEmpty)
    }

    @Test("Filters loaded rows locally")
    func filtersLoadedRows() async {
        let paginationIssue = makeTestIssue(
            id: 1,
            iid: 1,
            title: "Fix Pagination",
            labels: ["backend"],
            assignees: [
                makeTestIssueUser(
                    username: "monalisa",
                    name: "Mona Lisa"
                ),
            ],
            reference: "group/api#1"
        )
        let interfaceIssue = makeTestIssue(
            id: 2,
            iid: 2,
            title: "Polish interface",
            labels: ["iOS"],
            reference: "group/app#2"
        )
        let loader = StubIssueLoader(
            pageResults: [
                .success(
                    GitLabIssuePage(
                        issues: [paginationIssue, interfaceIssue],
                        nextPageURL: nil
                    )
                ),
            ]
        )
        let model = AssignedIssuesModel(loader: loader)
        await model.loadIfNeeded()

        for query in [
            "pagination",
            "API#1",
            "BACKEND",
            "móna",
            "monalisa",
        ] {
            model.searchText = query
            #expect(model.displayedIssues.map(\.id) == [1])
        }

        model.searchText = "ios"
        #expect(model.displayedIssues.map(\.id) == [2])
        model.searchText = " "
        #expect(model.displayedIssues.map(\.id) == [1, 2])
    }

    @Test("Reconciles an edited issue only when its row is loaded")
    func reconcilesLoadedEditedIssue() async {
        let original = makeTestIssue(
            title: "Original"
        )
        let edited = makeTestIssue(
            title: "Edited"
        )
        let missing = makeTestIssue(
            id: 202,
            iid: 8,
            title: "Missing"
        )
        let model = AssignedIssuesModel(
            loader: StubIssueLoader(
                pageResults: [
                    .success(
                        GitLabIssuePage(
                            issues: [original],
                            nextPageURL: nil
                        )
                    ),
                ]
            )
        )

        #expect(!model.reconcileItemIfPresent(edited))
        await model.loadIfNeeded()

        #expect(model.reconcileItemIfPresent(edited))
        #expect(model.issues == [edited])
        #expect(!model.reconcileItemIfPresent(missing))
        #expect(model.issues == [edited])
    }

    @Test("Refresh replaces loaded rows")
    func refreshesRows() async {
        let original = makeTestIssue(id: 1, iid: 1)
        let refreshed = makeTestIssue(id: 2, iid: 2)
        let loader = StubIssueLoader(
            pageResults: [
                .success(
                    GitLabIssuePage(
                        issues: [original],
                        nextPageURL: nil
                    )
                ),
                .success(
                    GitLabIssuePage(
                        issues: [refreshed],
                        nextPageURL: nil
                    )
                ),
            ]
        )
        let model = AssignedIssuesModel(loader: loader)

        await model.loadIfNeeded()
        await model.refresh()

        #expect(model.issues == [refreshed])
        #expect(model.loadError == nil)
    }

    @Test("Preserves rows and reports a failed refresh")
    func preservesRowsAfterRefreshFailure() async throws {
        let original = makeTestIssue(id: 1, iid: 1)
        let refreshed = makeTestIssue(id: 2, iid: 2)
        let staleNextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/issues?page=2"
            )
        )
        let loader = StubIssueLoader(
            pageResults: [
                .success(
                    GitLabIssuePage(
                        issues: [original],
                        nextPageURL: staleNextPageURL
                    )
                ),
                .failure(.api(.server(statusCode: 503))),
                .success(
                    GitLabIssuePage(
                        issues: [refreshed],
                        nextPageURL: nil
                    )
                ),
            ]
        )
        let model = AssignedIssuesModel(loader: loader)

        await model.loadIfNeeded()
        await model.refresh()

        #expect(model.issues == [original])
        #expect(model.didFailRefresh)
        #expect(
            model.loadError == .api(.server(statusCode: 503))
        )

        await model.loadNextPageIfNeeded(after: original)

        #expect(model.didFailRefresh)
        #expect(!model.didFailNextPage)
        #expect(
            await loader.pageRequestURLs == [nil, nil]
        )

        await model.refresh()

        #expect(model.issues == [refreshed])
        #expect(!model.didFailRefresh)
        #expect(model.loadError == nil)
    }

    @Test("Preserves rows when an incremental load fails")
    func preservesRowsAfterPageFailure() async throws {
        let issue = makeTestIssue()
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/issues?page=2"
            )
        )
        let loader = StubIssueLoader(
            pageResults: [
                .success(
                    GitLabIssuePage(
                        issues: [issue],
                        nextPageURL: nextPageURL
                    )
                ),
                .failure(.api(.server(statusCode: 503))),
            ]
        )
        let model = AssignedIssuesModel(loader: loader)

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(after: issue)

        #expect(model.issues == [issue])
        #expect(model.nextPageURL == nextPageURL)
        #expect(model.didFailNextPage)
        #expect(
            model.loadError == .api(.server(statusCode: 503))
        )
    }

    @Test("Treats request cancellation as a non-result")
    func ignoresCancellation() async {
        let loader = StubIssueLoader(
            pageResults: [
                .failure(.api(.cancelled)),
            ]
        )
        let model = AssignedIssuesModel(loader: loader)

        await model.loadIfNeeded()

        #expect(!model.hasLoaded)
        #expect(model.loadError == nil)
        #expect(model.issues.isEmpty)
    }

    @Test("Exposes authentication failures")
    func exposesAuthenticationFailure() async {
        let loader = StubIssueLoader(
            pageResults: [
                .failure(.api(.unauthenticated)),
            ]
        )
        let model = AssignedIssuesModel(loader: loader)

        await model.loadIfNeeded()

        #expect(
            model.authenticationFailure
                == .api(.unauthenticated)
        )
    }

    @Test(
        "Formats compact relative times",
        arguments: [
            (0.0, "now"),
            (59.0, "now"),
            (60.0, "1m"),
            (3_599.0, "59m"),
            (3_600.0, "1h"),
            (86_400.0, "1d"),
            (604_800.0, "1w"),
            (31_536_000.0, "1y"),
        ]
    )
    func formatsRelativeTime(
        elapsed: TimeInterval,
        expected: String
    ) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(
            GitLabRelativeTimeFormatter.string(
                from: now.addingTimeInterval(-elapsed),
                relativeTo: now
            ) == expected
        )
    }

    @Test("Formats GitLab date-only values")
    func formatsDueDate() {
        #expect(
            GitLabIssueDateFormatter.dueDate(
                "2026-07-27",
                locale: Locale(identifier: "en_US")
            ) == "Jul 27, 2026"
        )
        #expect(
            GitLabIssueDateFormatter.dueDate(
                "not-a-date",
                locale: Locale(identifier: "en_US")
            ) == nil
        )
    }

}

@Suite("GitLab issue detail model")
@MainActor
struct GitLabIssueDetailModelTests {
    @Test("Loads issue details once")
    func loadsDetailOnce() async {
        let issue = makeTestIssue()
        let loader = StubIssueLoader(
            issueResults: [
                .success(issue),
            ]
        )
        let model = GitLabIssueDetailModel(
            route: issue.route,
            loader: loader
        )

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(model.state == .loaded(issue))
        #expect(await loader.issueRoutes == [issue.route])
    }

    @Test("Reports failures and retries")
    func retriesDetail() async {
        let issue = makeTestIssue()
        let loader = StubIssueLoader(
            issueResults: [
                .failure(.api(.server(statusCode: 503))),
                .success(issue),
            ]
        )
        let model = GitLabIssueDetailModel(
            route: issue.route,
            loader: loader
        )

        await model.loadIfNeeded()
        #expect(
            model.state
                == .failed(.api(.server(statusCode: 503)))
        )

        await model.retry()
        #expect(model.state == .loaded(issue))
    }

    @Test("Restores detail state after cancellation")
    func restoresStateAfterCancellation() async {
        let issue = makeTestIssue()
        let loader = StubIssueLoader(
            issueResults: [
                .failure(.api(.cancelled)),
            ]
        )
        let model = GitLabIssueDetailModel(
            route: issue.route,
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(model.state == .idle)
    }

    @Test("Keeps a cached detail when revalidation fails")
    func preservesCachedDetailAfterFailure() async {
        let issue = makeTestIssue()
        let edited = makeTestIssue(title: "Edited")
        let failure = GitLabSessionClientError.api(
            .server(statusCode: 500)
        )
        let storedAt = Date(
            timeIntervalSince1970: 10_000
        )
        let loader = StaleIssueDetailLoader(
            issue: issue,
            failure: failure,
            storedAt: storedAt
        )
        let model = GitLabIssueDetailModel(
            route: issue.route,
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(model.state == .loaded(issue))
        #expect(model.refreshError == failure)
        #expect(
            model.resourceSource == .cache(.stale)
        )
        #expect(model.cacheStoredAt == storedAt)
        #expect(
            await loader.refreshBehaviors
                == [.ifStale]
        )

        #expect(model.reconcileAuthoritative(edited))
        #expect(model.state == .loaded(edited))
        #expect(model.refreshError == nil)
        #expect(model.resourceSource == .network)
        #expect(model.cacheStoredAt == nil)
    }

    @Test("Does not insert an edited issue into an idle detail")
    func doesNotReconcileIdleDetail() {
        let issue = makeTestIssue()
        let model = GitLabIssueDetailModel(
            route: issue.route,
            loader: StubIssueLoader()
        )

        #expect(!model.reconcileAuthoritative(issue))
        #expect(model.state == .idle)
    }
}

private actor StaleIssueDetailLoader:
    GitLabIssueLoading
{
    let issue: GitLabIssue
    let failure: GitLabSessionClientError
    let storedAt: Date
    private(set) var refreshBehaviors:
        [GitLabCacheRefreshBehavior] = []

    init(
        issue: GitLabIssue,
        failure: GitLabSessionClientError,
        storedAt: Date
    ) {
        self.issue = issue
        self.failure = failure
        self.storedAt = storedAt
    }

    func loadIssuesPage(
        for mode: GitLabIssueListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabIssuePage
    {
        throw .api(.invalidResponse)
    }

    func loadIssue(
        at route: GitLabIssueRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabIssue
    {
        throw failure
    }

    func loadIssue(
        at route: GitLabIssueRoute,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<GitLabIssue>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        refreshBehaviors.append(refreshBehavior)
        await onResponse(
            GitLabAPIResponseEvent(
                value: issue,
                metadata: GitLabResponseMetadata(),
                source: .cache(.stale),
                cacheStoredAt: storedAt
            )
        )
        throw failure
    }
}

private actor StubIssueLoader: GitLabIssueLoading {
    private var pageResults: [
        Result<GitLabIssuePage, GitLabSessionClientError>
    ]
    private var issueResults: [
        Result<GitLabIssue, GitLabSessionClientError>
    ]
    private(set) var pageRequestURLs: [URL?] = []
    private(set) var modes:
        [GitLabIssueListMode] = []
    private(set) var issueRoutes: [GitLabIssueRoute] = []

    init(
        pageResults: [
            Result<GitLabIssuePage, GitLabSessionClientError>
        ] = [],
        issueResults: [
            Result<GitLabIssue, GitLabSessionClientError>
        ] = []
    ) {
        self.pageResults = pageResults
        self.issueResults = issueResults
    }

    func loadIssuesPage(
        for mode: GitLabIssueListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError) -> GitLabIssuePage {
        modes.append(mode)
        pageRequestURLs.append(nextPageURL)
        guard !pageResults.isEmpty else {
            throw .api(.invalidResponse)
        }

        return try pageResults.removeFirst().get()
    }

    func loadIssue(
        at route: GitLabIssueRoute
    ) async throws(GitLabSessionClientError) -> GitLabIssue {
        issueRoutes.append(route)
        guard !issueResults.isEmpty else {
            throw .api(.invalidResponse)
        }

        return try issueResults.removeFirst().get()
    }
}
