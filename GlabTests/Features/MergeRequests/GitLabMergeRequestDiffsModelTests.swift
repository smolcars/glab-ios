import Foundation
import Testing
@testable import Glab

@Suite("GitLab merge request diffs model")
@MainActor
struct GitLabMergeRequestDiffsModelTests {
    @Test("Replaces a cached first page with network results")
    func cachedThenNetwork() async throws {
        let cached = makeTestDiffFile(
            newPath: "Sources/Cached.swift"
        )
        let network = makeTestDiffFile(
            newPath: "Sources/Network.swift"
        )
        let loader = StubMergeRequestDiffLoader(
            firstPageEvents: [
                GitLabResourcePageEvent(
                    page: GitLabResourcePage(
                        items: [cached],
                        nextPageURL: nil
                    ),
                    source: .cache(.stale)
                ),
                GitLabResourcePageEvent(
                    page: GitLabResourcePage(
                        items: [network],
                        nextPageURL: nil,
                        totalCount: 1
                    ),
                    source: .network
                ),
            ]
        )
        let model = GitLabMergeRequestDiffsModel(
            route: route,
            headSHA: "head-sha",
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(model.files == [network])
        #expect(model.reliableItemCount == 1)
        #expect(model.firstPageSource == .network)
        #expect(
            await loader.requestedHeads
                == ["head-sha"]
        )
    }

    @Test("Appends pages without duplicate path-pair identities")
    func pagination() async throws {
        let first = makeTestDiffFile(
            newPath: "Sources/First.swift"
        )
        let duplicate = makeTestDiffFile(
            newPath: "Sources/First.swift",
            diff: "@@ -1 +1 @@\n-old\n+updated"
        )
        let second = makeTestDiffFile(
            newPath: "Sources/Second.swift"
        )
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "projects/42/merge_requests/7/"
                    + "diffs?page=2"
            )
        )
        let loader = StubMergeRequestDiffLoader(
            pageResults: [
                .success(
                    GitLabMergeRequestDiffPage(
                        files: [first],
                        nextPageURL: nextPageURL,
                        totalCount: 2
                    )
                ),
                .success(
                    GitLabMergeRequestDiffPage(
                        files: [duplicate, second],
                        nextPageURL: nil,
                        totalCount: 2
                    )
                ),
            ]
        )
        let model = GitLabMergeRequestDiffsModel(
            route: route,
            headSHA: "head-sha",
            loader: loader
        )

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(
            after: try #require(model.files.last)
        )

        #expect(model.files == [first, second])
        #expect(model.reliableItemCount == 2)
        #expect(
            await loader.requestedPageURLs
                == [nil, nextPageURL]
        )
    }

    @Test("Searches both sides of a renamed path")
    func searchPaths() async {
        let renamed = makeTestDiffFile(
            oldPath: "Sources/Legacy.swift",
            newPath: "Sources/Current.swift",
            isRenamedFile: true
        )
        let loader = StubMergeRequestDiffLoader(
            pageResults: [
                .success(
                    GitLabMergeRequestDiffPage(
                        files: [renamed],
                        nextPageURL: nil,
                        totalCount: 1
                    )
                ),
            ]
        )
        let model = GitLabMergeRequestDiffsModel(
            route: route,
            headSHA: "head-sha",
            loader: loader
        )
        await model.loadIfNeeded()

        model.searchText = "legacy"
        #expect(model.displayedFiles == [renamed])
        model.searchText = "current"
        #expect(model.displayedFiles == [renamed])
    }

    private var route: GitLabMergeRequestRoute {
        GitLabMergeRequestRoute(
            projectID: 42,
            mergeRequestIID: 7
        )
    }
}

private actor StubMergeRequestDiffLoader:
    GitLabMergeRequestDiffLoading
{
    private let firstPageEvents:
        [
            GitLabResourcePageEvent<
                GitLabMergeRequestDiffFile
            >
        ]
    private var pageResults:
        [
            Result<
                GitLabMergeRequestDiffPage,
                GitLabSessionClientError
            >
        ]
    private(set) var requestedHeads:
        [String] = []
    private(set) var requestedPageURLs:
        [URL?] = []

    init(
        firstPageEvents:
            [
                GitLabResourcePageEvent<
                    GitLabMergeRequestDiffFile
                >
            ] = [],
        pageResults:
            [
                Result<
                    GitLabMergeRequestDiffPage,
                    GitLabSessionClientError
                >
            ] = []
    ) {
        self.firstPageEvents = firstPageEvents
        self.pageResults = pageResults
    }

    func loadMergeRequestDiffsPage(
        at route: GitLabMergeRequestRoute,
        headSHA: String,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestDiffPage
    {
        requestedHeads.append(headSHA)
        requestedPageURLs.append(nextPageURL)
        guard !pageResults.isEmpty else {
            return GitLabMergeRequestDiffPage(
                files: [],
                nextPageURL: nil,
                totalCount: 0
            )
        }
        return try pageResults.removeFirst().get()
    }

    func loadMergeRequestDiffsFirstPage(
        at route: GitLabMergeRequestRoute,
        headSHA: String,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabMergeRequestDiffFile
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        guard !firstPageEvents.isEmpty else {
            let page =
                try await loadMergeRequestDiffsPage(
                    at: route,
                    headSHA: headSHA,
                    after: nil
                )
            await onPage(
                GitLabResourcePageEvent(
                    page: GitLabResourcePage(
                        items: page.files,
                        nextPageURL:
                            page.nextPageURL,
                        totalCount:
                            page.totalCount
                    ),
                    source: .network
                )
            )
            return
        }

        requestedHeads.append(headSHA)
        for event in firstPageEvents {
            await onPage(event)
        }
    }
}
