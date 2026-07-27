import Foundation
import Testing
@testable import Glab

@Suite("Merge requests model")
@MainActor
struct MergeRequestsModelTests {
    @Test("Appends pages without duplicate routes")
    func appendsPagesWithoutDuplicates() async throws {
        let first = makeTestMergeRequest(
            id: 1,
            iid: 1,
            title: "First"
        )
        let second = makeTestMergeRequest(
            id: 2,
            iid: 2,
            title: "Second"
        )
        let duplicateSecond = makeTestMergeRequest(
            id: 20,
            iid: 2,
            title: "Duplicate second"
        )
        let third = makeTestMergeRequest(
            id: 3,
            iid: 3,
            title: "Third"
        )
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "merge_requests?page=2"
            )
        )
        let loader = StubMergeRequestLoader(
            pageResults: [
                .success(
                    GitLabMergeRequestPage(
                        mergeRequests: [first, second],
                        nextPageURL: nextPageURL
                    )
                ),
                .success(
                    GitLabMergeRequestPage(
                        mergeRequests: [duplicateSecond, third],
                        nextPageURL: nil
                    )
                ),
            ]
        )
        let model = MergeRequestsModel(
            mode: .reviewRequested,
            loader: loader
        )

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(
            after: try #require(model.mergeRequests.last)
        )

        #expect(
            model.mergeRequests.map(\.title)
                == ["First", "Second", "Third"]
        )
        #expect(model.nextPageURL == nil)
        #expect(
            await loader.pageModes
                == [.reviewRequested, .reviewRequested]
        )
        #expect(
            await loader.pageRequestURLs
                == [nil, nextPageURL]
        )
    }

    @Test("Filters loaded rows locally")
    func filtersLoadedRows() async {
        let pagination = makeTestMergeRequest(
            id: 1,
            iid: 1,
            title: "Fix Pagination",
            labels: ["backend"],
            author: makeTestAPIUser(
                username: "octocat",
                name: "The Octocat"
            ),
            assignees: [
                makeTestAPIUser(
                    id: 2,
                    username: "monalisa",
                    name: "Mona Lisa"
                ),
            ],
            reviewers: [
                makeTestAPIUser(
                    id: 3,
                    username: "hubot",
                    name: "Hubot"
                ),
            ],
            sourceBranch: "feature/cursor",
            targetBranch: "release",
            reference: "group/api!1"
        )
        let interface = makeTestMergeRequest(
            id: 2,
            iid: 2,
            title: "Polish interface",
            labels: ["iOS"],
            author: makeTestAPIUser(
                id: 4,
                username: "swiftcat",
                name: "Swift Cat"
            ),
            sourceBranch: "feature/ui",
            targetBranch: "main",
            reference: "group/app!2"
        )
        let loader = StubMergeRequestLoader(
            pageResults: [
                .success(
                    GitLabMergeRequestPage(
                        mergeRequests: [pagination, interface],
                        nextPageURL: nil
                    )
                ),
            ]
        )
        let model = MergeRequestsModel(
            mode: .assigned,
            loader: loader
        )
        await model.loadIfNeeded()

        for query in [
            "pagination",
            "API!1",
            "BACKEND",
            "octocat",
            "móna",
            "hubot",
            "cursor",
            "release",
        ] {
            model.searchText = query
            #expect(
                model.displayedMergeRequests.map(\.id) == [1]
            )
        }

        model.searchText = "ios"
        #expect(
            model.displayedMergeRequests.map(\.id) == [2]
        )
        model.searchText = " "
        #expect(
            model.displayedMergeRequests.map(\.id) == [1, 2]
        )
    }

    @Test("Preserves rows and reports a failed refresh")
    func preservesRowsAfterRefreshFailure() async throws {
        let original = makeTestMergeRequest(id: 1, iid: 1)
        let refreshed = makeTestMergeRequest(id: 2, iid: 2)
        let staleNextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "merge_requests?page=2"
            )
        )
        let loader = StubMergeRequestLoader(
            pageResults: [
                .success(
                    GitLabMergeRequestPage(
                        mergeRequests: [original],
                        nextPageURL: staleNextPageURL
                    )
                ),
                .failure(.api(.server(statusCode: 503))),
                .success(
                    GitLabMergeRequestPage(
                        mergeRequests: [refreshed],
                        nextPageURL: nil
                    )
                ),
            ]
        )
        let model = MergeRequestsModel(
            mode: .assigned,
            loader: loader
        )

        await model.loadIfNeeded()
        await model.refresh()

        #expect(model.mergeRequests == [original])
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

        #expect(model.mergeRequests == [refreshed])
        #expect(!model.didFailRefresh)
        #expect(model.loadError == nil)
    }

    @Test("Preserves rows when an incremental load fails")
    func preservesRowsAfterPageFailure() async throws {
        let mergeRequest = makeTestMergeRequest()
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "merge_requests?page=2"
            )
        )
        let loader = StubMergeRequestLoader(
            pageResults: [
                .success(
                    GitLabMergeRequestPage(
                        mergeRequests: [mergeRequest],
                        nextPageURL: nextPageURL
                    )
                ),
                .failure(.api(.server(statusCode: 503))),
            ]
        )
        let model = MergeRequestsModel(
            mode: .assigned,
            loader: loader
        )

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(
            after: mergeRequest
        )

        #expect(model.mergeRequests == [mergeRequest])
        #expect(model.nextPageURL == nextPageURL)
        #expect(model.didFailNextPage)
        #expect(
            model.loadError == .api(.server(statusCode: 503))
        )
    }

    @Test("Treats cancellation as a non-result")
    func ignoresCancellation() async {
        let loader = StubMergeRequestLoader(
            pageResults: [
                .failure(.api(.cancelled)),
            ]
        )
        let model = MergeRequestsModel(
            mode: .assigned,
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(!model.hasLoaded)
        #expect(model.loadError == nil)
        #expect(model.mergeRequests.isEmpty)
    }

    @Test("Exposes authentication failures")
    func exposesAuthenticationFailure() async {
        let loader = StubMergeRequestLoader(
            pageResults: [
                .failure(.api(.unauthenticated)),
            ]
        )
        let model = MergeRequestsModel(
            mode: .assigned,
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(
            model.authenticationFailure
                == .api(.unauthenticated)
        )
    }
}

@Suite("GitLab merge request detail model")
@MainActor
struct GitLabMergeRequestDetailModelTests {
    @Test("Loads merge request details once")
    func loadsDetailOnce() async {
        let mergeRequest = makeTestMergeRequest()
        let loader = StubMergeRequestLoader(
            detailResults: [
                .success(mergeRequest),
            ]
        )
        let model = GitLabMergeRequestDetailModel(
            route: mergeRequest.route,
            loader: loader
        )

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(model.state == .loaded(mergeRequest))
        #expect(
            await loader.detailRoutes
                == [mergeRequest.route]
        )
    }

    @Test("Reports failures and retries")
    func retriesDetail() async {
        let mergeRequest = makeTestMergeRequest()
        let loader = StubMergeRequestLoader(
            detailResults: [
                .failure(.api(.server(statusCode: 503))),
                .success(mergeRequest),
            ]
        )
        let model = GitLabMergeRequestDetailModel(
            route: mergeRequest.route,
            loader: loader
        )

        await model.loadIfNeeded()
        #expect(
            model.state
                == .failed(.api(.server(statusCode: 503)))
        )

        await model.retry()
        #expect(model.state == .loaded(mergeRequest))
    }

    @Test("Restores detail state after cancellation")
    func restoresStateAfterCancellation() async {
        let mergeRequest = makeTestMergeRequest()
        let loader = StubMergeRequestLoader(
            detailResults: [
                .failure(.api(.cancelled)),
            ]
        )
        let model = GitLabMergeRequestDetailModel(
            route: mergeRequest.route,
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(model.state == .idle)
    }

    @Test("Exposes detail authentication failures")
    func exposesAuthenticationFailure() async {
        let mergeRequest = makeTestMergeRequest()
        let loader = StubMergeRequestLoader(
            detailResults: [
                .failure(.api(.unauthenticated)),
            ]
        )
        let model = GitLabMergeRequestDetailModel(
            route: mergeRequest.route,
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(
            model.authenticationFailure
                == .api(.unauthenticated)
        )
    }
}

private actor StubMergeRequestLoader:
    GitLabMergeRequestLoading
{
    private var pageResults: [
        Result<GitLabMergeRequestPage, GitLabSessionClientError>
    ]
    private var detailResults: [
        Result<GitLabMergeRequest, GitLabSessionClientError>
    ]
    private(set) var pageModes: [GitLabMergeRequestListMode] = []
    private(set) var pageRequestURLs: [URL?] = []
    private(set) var detailRoutes: [GitLabMergeRequestRoute] = []

    init(
        pageResults: [
            Result<GitLabMergeRequestPage, GitLabSessionClientError>
        ] = [],
        detailResults: [
            Result<GitLabMergeRequest, GitLabSessionClientError>
        ] = []
    ) {
        self.pageResults = pageResults
        self.detailResults = detailResults
    }

    func loadMergeRequestsPage(
        for mode: GitLabMergeRequestListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestPage
    {
        pageModes.append(mode)
        pageRequestURLs.append(nextPageURL)
        guard !pageResults.isEmpty else {
            throw .api(.invalidResponse)
        }

        return try pageResults.removeFirst().get()
    }

    func loadMergeRequest(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequest
    {
        detailRoutes.append(route)
        guard !detailResults.isEmpty else {
            throw .api(.invalidResponse)
        }

        return try detailResults.removeFirst().get()
    }
}
